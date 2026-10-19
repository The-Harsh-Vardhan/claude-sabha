/* @jsx h */
import type { EngineInterface, Register, RenderElement, SessionMeasureInput, Timer } from 'claude-code'

import {
  addTokens,
  cellsOf,
  paneOf,
  sabhaFileOf,
  sabhaLimitsOf,
  statusOf,
  ZERO,
  type Snapshot,
  type Tokens,
} from './deck'

// sabha-deck: one table for the session, in the band above the prompt (terminal and VS Code), a /deck pane and the
// status line: session name, context, the 5-hour and weekly quota with their resets, subagents, tokens and cost.
// With the `sabhaImpl` option set it also writes claude-sabha's status/context/<name>.txt and status/limits.txt,
// so the restart loop and the board work without the bash status line.

const PANE_ID = 'deck'
const STORE_KEY = 'tokens'
const BAND_KEY = 'bandHidden'
const TICK_MS = 30_000

let name = ''
let main: Tokens = ZERO
let sub: Tokens = ZERO
let sessionId: string | null = null
let limitsAtStart: Record<string, number> = {}
let snap: Snapshot | null = null
let isPaneOpen = false
let isBandHidden = false
let tick: Timer | null = null
let lastSabha = ''
let lastMeasure: Pick<SessionMeasureInput, 'context' | 'rateLimits' | 'cost'> | null = null
let firstSeenMs: number | null = null

const quietly = async <T,>(work: () => Promise<T>): Promise<T | null> => {
  try {
    return await work()
  } catch {
    return null
  }
}

async function save($: EngineInterface): Promise<void> {
  await quietly(() => $.store.set(STORE_KEY, { sessionId, main, sub, limitsAtStart }))
}

/** A resumed session (same transcript id) picks its token totals back up; a new one starts at zero. */
async function restore($: EngineInterface): Promise<void> {
  main = ZERO
  sub = ZERO
  limitsAtStart = {}
  sessionId = await quietly(() => $.session.id())
  const held = (await quietly(() => $.store.get(STORE_KEY))) as Record<string, unknown> | null
  if (!held || sessionId === null || held['sessionId'] !== sessionId) return
  main = addTokens(ZERO, (held['main'] ?? {}) as Partial<Tokens>)
  sub = addTokens(ZERO, (held['sub'] ?? {}) as Partial<Tokens>)
  limitsAtStart = (held['limitsAtStart'] ?? {}) as Record<string, number>
}

/** Writes sabha's files when a project folder is configured and a figure moved. */
async function feedSabha($: EngineInterface, impl: string, s: Snapshot): Promise<void> {
  if (!impl || !s.name) return
  const pct = s.ctx.percent === undefined ? '' : String(Math.round(s.ctx.percent))
  const limits = sabhaLimitsOf(s.limits, s.nowMs)
  // the written epoch changes every call; compare without it
  const key = `${s.name}|${pct}|${limits.replace(/ \d+\n/g, '\n')}`
  if (key === lastSabha) return
  lastSabha = key
  const root = impl.replace(/[\\/]+$/, '')
  if (pct) await quietly(() => $.fs.write(`${root}/status/context/${sabhaFileOf(s.name)}.txt`, `${pct}\n`))
  if (limits) await quietly(() => $.fs.write(`${root}/status/limits.txt`, limits))
}

async function refresh($: EngineInterface, impl: string): Promise<void> {
  const nowMs = (await quietly(() => $.clock.now())) ?? Date.now()
  // usage() is the live read; the last session.measure carries the same figures where it is not available
  const usage =
    (await quietly(() => $.session.usage())) ?? (lastMeasure ? { ...lastMeasure, startedAt: firstSeenMs ?? nowMs } : null)
  if (!usage) return
  const agents = (await quietly(() => $.agent.list())) ?? []
  const limits = (usage.rateLimits ?? []).map(l => ({ kind: l.kind, percentUsed: l.percentUsed, resetsAt: l.resetsAt }))

  let moved = false
  for (const l of limits) {
    if (limitsAtStart[l.kind] === undefined && Number.isFinite(l.percentUsed)) {
      limitsAtStart[l.kind] = l.percentUsed
      moved = true
    }
  }
  if (moved) await save($)

  snap = {
    name,
    model: (await quietly(() => $.session.model())) ?? '',
    turns: (await quietly(() => $.session.turns())) ?? 0,
    startedAt: usage.startedAt,
    nowMs,
    ctx: { percent: usage.context.percent, tokens: usage.context.tokens, window: usage.context.window },
    limits,
    // $.agent.list() holds subagents and teammates, never the main loop
    agents: agents.map(a => ({ label: `${a.name ?? a.type}: ${a.description}`.slice(0, 80), status: a.status })),
    main,
    sub,
    usd: usage.cost?.usd ?? null,
    limitsAtStart,
  }

  try {
    $.ui.status(statusOf(snap))
  } catch {
    // a status line that will not pin costs nothing
  }
  await feedSabha($, impl, snap)
  try {
    $.ui.invalidate('ui.render')
  } catch {
    // the next tick redraws
  }
}

export const register: Register = (on, options) => {
  const impl = typeof options['sabhaImpl'] === 'string' ? options['sabhaImpl'] : ''

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await restore($)
    isBandHidden = (await quietly(() => $.store.get(BAND_KEY))) === true
    await quietly(() =>
      $.command.register({
        name: 'deck',
        description: 'Session deck: context, 5h and weekly quota, subagents, tokens, cost (sabha-deck)',
        argumentHint: '[band]',
      }),
    )
    await refresh($, impl)
    try {
      tick?.cancel()
      tick = $.clock.every(TICK_MS, () => void refresh($, impl))
    } catch {
      // without the tick the deck still updates after every turn
    }
    return result
  })

  // the session's name (claude -n Relay, or /rename) rides on the classic events; a sabha role is its name
  on('classic.SessionStart', async ($, e, next) => {
    if (e.session_title) name = e.session_title
    return next(e)
  })
  on('classic.UserPromptSubmit', async ($, e, next) => {
    if (e.session_title && e.session_title !== name) {
      name = e.session_title
      void refresh($, impl)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    const u = e.usage
    if (u) {
      const t = {
        input: u.input_tokens ?? 0,
        output: u.output_tokens ?? 0,
        cacheRead: u.cache_read_input_tokens ?? 0,
        cacheWrite: u.cache_creation_input_tokens ?? 0,
      }
      if (e.agentId === undefined) main = addTokens(main, t)
      else sub = addTokens(sub, t)
      await save($)
    }
    await refresh($, impl)
    return result
  })

  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    lastMeasure = { context: e.context, rateLimits: e.rateLimits, cost: e.cost }
    firstSeenMs ??= (await quietly(() => $.clock.now())) ?? Date.now()
    void refresh($, impl)
    return result
  })

  for (const command of ['clear', 'resume'] as const) {
    on('command.run', { command }, async ($, e, next) => {
      const result = await next(e)
      await restore($)
      await refresh($, impl)
      return result
    })
  }

  on('command.run', { command: 'deck' }, async ($, e, next) => {
    if (e.args.trim() === 'band') {
      isBandHidden = !isBandHidden
      await quietly(() => $.store.set(BAND_KEY, isBandHidden))
      await quietly(async () => $.ui.invalidate('ui.render'))
      return { text: isBandHidden ? 'Deck band hidden. /deck band shows it.' : 'Deck band shown.' }
    }
    if (isPaneOpen) {
      await quietly(() => $.ui.close({ id: PANE_ID }))
      isPaneOpen = false
      return { text: 'Deck closed. /deck opens it again.' }
    }
    await refresh($, impl)
    const opened = await quietly(() => $.ui.open({ id: PANE_ID, title: 'Session deck', rows: 26 }))
    if (opened === null) return { text: snap ? `sabha-deck: the pane did not open. ${statusOf(snap)}` : 'sabha-deck: the pane did not open' }
    isPaneOpen = true
    return { text: 'Deck open. /deck closes it; /deck band toggles the row above the prompt.' }
  })

  on('ui.close', { id: PANE_ID }, async ($, e, next) => {
    const result = await next(e)
    if (result.deny === undefined) isPaneOpen = false
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (isBandHidden || snap === null || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const cells = cellsOf(snap)
    return (
      <Box flexDirection="row" flexWrap="wrap">
        {cells.map(([label, value, color], i) => (
          <Text key={String(i)} wrap="truncate-end">
            {i > 0 ? <Text dimColor>{' | '}</Text> : ''}
            {label ? <Text dimColor>{`${label} `}</Text> : ''}
            <Text bold={i === 0} color={color}>
              {value}
            </Text>
          </Text>
        ))}
      </Box>
    ) as RenderElement
  })

  on('ui.render', { component: 'Pane' }, ($, e, next) => {
    if (e.requestId !== PANE_ID) return next(e)
    isPaneOpen = true
    const { Box, Text } = $.ui.resolve(e)
    if (snap === null) {
      return (
        <Box>
          <Text dimColor>No reading yet. It fills in after the first answer.</Text>
        </Box>
      ) as RenderElement
    }
    const sections = paneOf(snap)
    const w = Math.max(...sections.flatMap(([, rows]) => rows.map(([k]) => k.length)), 6) + 2
    return (
      <Box flexDirection="column" paddingX={1}>
        {sections.map(([title, rows]) => (
          <Box key={title} flexDirection="column" marginBottom={1}>
            <Text bold>{title}</Text>
            {rows.map(([k, v, d], i) => (
              <Text key={`${title}${i}`} wrap="truncate-end">
                <Text dimColor>{`  ${k.padEnd(w)}`}</Text>
                <Text bold>{v.padEnd(8)}</Text>
                <Text dimColor>{d}</Text>
              </Text>
            ))}
          </Box>
        ))}
        <Text dimColor>Updates after each turn and every 30s. /deck closes this pane.</Text>
      </Box>
    ) as RenderElement
  })
}
