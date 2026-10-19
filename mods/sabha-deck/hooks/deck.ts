// Pure formatting for sabha-deck: no `$`, so every figure the band, the pane and the status line show is testable.

export type Limit = { kind: string; percentUsed: number; resetsAt?: string }
export type AgentRow = { label: string; status: string }
export type Tokens = { input: number; output: number; cacheRead: number; cacheWrite: number }

export type Snapshot = {
  name: string
  model: string
  turns: number
  startedAt: number
  nowMs: number
  ctx: { percent?: number; tokens?: number; window: number }
  limits: Limit[]
  agents: AgentRow[]
  main: Tokens
  sub: Tokens
  usd: number | null
  /** percentUsed of each window when the session started, for the burn figure */
  limitsAtStart: Record<string, number>
}

export const ZERO: Tokens = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }

const LIVE = new Set(['pending', 'running', 'waiting'])

export function addTokens(a: Tokens, b: Partial<Tokens>): Tokens {
  return {
    input: a.input + (b.input ?? 0),
    output: a.output + (b.output ?? 0),
    cacheRead: a.cacheRead + (b.cacheRead ?? 0),
    cacheWrite: a.cacheWrite + (b.cacheWrite ?? 0),
  }
}

/** Tokens you were billed fresh for: input, output and cache writes. Cache reads are shown apart (they are cheap). */
export const freshOf = (t: Tokens): number => t.input + t.output + t.cacheWrite

export function fmtTok(n: number): string {
  if (n >= 1e6) return `${(n / 1e6).toFixed(n >= 1e7 ? 0 : 1)}M`
  if (n >= 1e3) return `${(n / 1e3).toFixed(n >= 1e4 ? 0 : 1)}k`
  return String(Math.round(n))
}

export function fmtPct(p: number | undefined): string {
  return p === undefined || !Number.isFinite(p) ? '--' : `${Math.round(p)}%`
}

export function fmtUsd(usd: number | null): string {
  if (usd === null) return '--'
  return usd >= 100 ? `$${usd.toFixed(0)}` : `$${usd.toFixed(2)}`
}

/** 0 -> "now", 45 min -> "45m", 2h10m, 3d4h. */
export function fmtSpan(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return 'now'
  const m = Math.floor(ms / 60000)
  if (m < 60) return `${m}m`
  const h = Math.floor(m / 60)
  if (h < 48) return `${h}h${String(m % 60).padStart(2, '0')}m`
  return `${Math.floor(h / 24)}d${h % 24}h`
}

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

/** Local clock time of a reset: "14:30" today, "Mon 09:30" on another day. */
export function fmtAt(iso: string | undefined, nowMs: number): string {
  if (!iso) return '--'
  const at = new Date(iso)
  if (Number.isNaN(at.getTime())) return '--'
  const hm = `${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')}`
  return new Date(nowMs).toDateString() === at.toDateString() ? hm : `${DAYS[at.getDay()]} ${hm}`
}

export function windowLabel(kind: string): string {
  if (kind === 'five_hour') return '5h'
  if (kind === 'seven_day') return 'week'
  if (kind === 'seven_day_opus') return 'week opus'
  if (kind === 'spend_limit') return 'spend'
  return kind.replace(/_/g, ' ')
}

export const resetInMs = (l: Limit, nowMs: number): number =>
  l.resetsAt ? new Date(l.resetsAt).getTime() - nowMs : NaN

/** green under 50, amber to 80, red from 80; context turns red earlier, at 30 (the sabha restart rule). */
export function colorOf(p: number | undefined, redAt = 80): string | undefined {
  if (p === undefined || !Number.isFinite(p)) return undefined
  if (p >= redAt) return 'red'
  if (p >= redAt * 0.6) return 'yellow'
  return 'green'
}

export const liveAgents = (s: Snapshot): number => s.agents.filter(a => LIVE.has(a.status)).length

/** The band's cells, left to right: [label, value, color?]. */
export function cellsOf(s: Snapshot): Array<[string, string, string | undefined]> {
  const cells: Array<[string, string, string | undefined]> = [
    ['', s.name || 'session', undefined],
    [
      'ctx',
      `${fmtPct(s.ctx.percent)}${s.ctx.tokens !== undefined ? ` ${fmtTok(s.ctx.tokens)}/${fmtTok(s.ctx.window)}` : ''}`,
      colorOf(s.ctx.percent, 30),
    ],
  ]
  for (const l of s.limits) {
    const when = l.kind === 'five_hour' ? fmtSpan(resetInMs(l, s.nowMs)) : fmtAt(l.resetsAt, s.nowMs)
    cells.push([windowLabel(l.kind), `${fmtPct(l.percentUsed)} ~${when}`, colorOf(l.percentUsed)])
  }
  if (s.limits.length === 0) cells.push(['quota', 'n/a', undefined])
  cells.push(['agents', `${liveAgents(s)}/${s.agents.length}`, undefined])
  cells.push(['tok', fmtTok(freshOf(s.main) + freshOf(s.sub)), undefined])
  cells.push(['cost', fmtUsd(s.usd), undefined])
  return cells
}

/** The status line: the band's cells on one line. */
export function statusOf(s: Snapshot): string {
  return cellsOf(s)
    .map(([k, v]) => (k ? `${k} ${v}` : v))
    .join(' | ')
}

/** Percent points used per hour since the session began, or null with too little time to say. */
export function burnOf(l: Limit, s: Snapshot): number | null {
  const start = s.limitsAtStart[l.kind]
  const hours = (s.nowMs - s.startedAt) / 3_600_000
  if (start === undefined || hours < 0.05) return null
  return Math.max(0, (l.percentUsed - start) / hours)
}

/** The pane: [section, rows of [label, value, detail]]. */
export function paneOf(s: Snapshot): Array<[string, Array<[string, string, string]>]> {
  const all = addTokens(s.main, s.sub)
  return [
    [
      'Session',
      [
        ['name', s.name || '(unnamed)', ''],
        ['model', s.model || '--', ''],
        ['turns', String(s.turns), `up ${fmtSpan(s.nowMs - s.startedAt)}`],
      ],
    ],
    [
      'Context',
      [
        [
          'used',
          fmtPct(s.ctx.percent),
          s.ctx.tokens !== undefined ? `${fmtTok(s.ctx.tokens)} of ${fmtTok(s.ctx.window)} tokens` : `window ${fmtTok(s.ctx.window)}`,
        ],
      ],
    ],
    [
      'Quota',
      s.limits.length === 0
        ? [['--', 'n/a', 'reported on Pro/Max plans after the first answer']]
        : s.limits.map(l => {
            const burn = burnOf(l, s)
            return [
              windowLabel(l.kind),
              fmtPct(l.percentUsed),
              `resets ${fmtAt(l.resetsAt, s.nowMs)} (in ${fmtSpan(resetInMs(l, s.nowMs))})` +
                (burn === null ? '' : `, ${burn.toFixed(1)}%/h this session`),
            ] as [string, string, string]
          }),
    ],
    [
      'Agents',
      [
        ['running', `${liveAgents(s)} of ${s.agents.length}`, ''],
        ...s.agents
          .slice(-8)
          .reverse()
          .map(a => ['', a.status, a.label] as [string, string, string]),
      ],
    ],
    [
      'Tokens',
      [
        ['fresh', fmtTok(freshOf(all)), `main ${fmtTok(freshOf(s.main))}, subagents ${fmtTok(freshOf(s.sub))}`],
        ['input', fmtTok(all.input), ''],
        ['output', fmtTok(all.output), ''],
        ['cache write', fmtTok(all.cacheWrite), ''],
        ['cache read', fmtTok(all.cacheRead), 'not counted in fresh'],
      ],
    ],
    ['Cost', [['session', fmtUsd(s.usd), '']]],
  ]
}

/** limits.txt as bin/sabha-limits.sh reads it: "<window> <used pct> <resets_at epoch> <written epoch>". */
export function sabhaLimitsOf(limits: Limit[], nowMs: number): string {
  const now = Math.floor(nowMs / 1000)
  return limits
    .filter(l => l.kind === 'five_hour' || l.kind === 'seven_day')
    .map(l => {
      const at = l.resetsAt ? Math.floor(new Date(l.resetsAt).getTime() / 1000) : 0
      return `${l.kind} ${Math.round(l.percentUsed)} ${Number.isFinite(at) ? at : 0} ${now}\n`
    })
    .join('')
}

/** status/context/<file>.txt name, as statusline-sabha.sh derives it from the session name. */
export const sabhaFileOf = (name: string): string => name.toLowerCase().replace(/[^a-z0-9._-]/g, '-')
