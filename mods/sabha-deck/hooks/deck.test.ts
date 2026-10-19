import { expect, test } from 'claude-code/testing'

import { burnOf, cellsOf, fmtSpan, fmtTok, paneOf, sabhaFileOf, sabhaLimitsOf, statusOf, ZERO, type Snapshot } from './deck'

const NOW = Date.UTC(2026, 9, 19, 10, 0, 0)
const iso = (msFromNow: number) => new Date(NOW + msFromNow).toISOString()

const snap = (over: Partial<Snapshot> = {}): Snapshot => ({
  name: 'Relay',
  model: 'claude-opus-5-5',
  turns: 4,
  startedAt: NOW - 2 * 3_600_000,
  nowMs: NOW,
  ctx: { percent: 42.4, tokens: 84_000, window: 200_000 },
  limits: [
    { kind: 'five_hour', percentUsed: 31, resetsAt: iso(2 * 3_600_000 + 10 * 60_000) },
    { kind: 'seven_day', percentUsed: 18, resetsAt: iso(3 * 86_400_000) },
  ],
  agents: [
    { label: 'Explore: find callers', status: 'running' },
    { label: 'general-purpose: docs', status: 'completed' },
  ],
  main: { input: 1_000, output: 20_000, cacheRead: 900_000, cacheWrite: 50_000 },
  sub: { input: 500, output: 5_000, cacheRead: 100_000, cacheWrite: 10_000 },
  usd: 4.2,
  limitsAtStart: { five_hour: 21, seven_day: 17 },
  ...over,
})

test('formats tokens and spans', async () => {
  expect(fmtTok(999)).toBe('999')
  expect(fmtTok(1_234)).toBe('1.2k')
  expect(fmtTok(86_500)).toBe('87k')
  expect(fmtTok(1_234_567)).toBe('1.2M')
  expect(fmtSpan(45 * 60_000)).toBe('45m')
  expect(fmtSpan(130 * 60_000)).toBe('2h10m')
  expect(fmtSpan(3 * 86_400_000 + 4 * 3_600_000)).toBe('3d4h')
  expect(fmtSpan(-5)).toBe('now')
})

test('the band shows name, context, both windows with resets, agents, fresh tokens and cost', async () => {
  const cells = cellsOf(snap())
  expect(cells[0]).toEqual(['', 'Relay', undefined])
  expect(cells[1][1]).toBe('42% 84k/200k')
  // context goes red at 30 percent, the sabha restart rule
  expect(cells[1][2]).toBe('red')
  expect(cells[2]).toEqual(['5h', '31% ~2h10m', 'green'])
  expect(cells[3][0]).toBe('week')
  expect(cells.find(c => c[0] === 'agents')?.[1]).toBe('1/2')
  // fresh = input + output + cache writes, main and subagents: 71k + 15.5k
  expect(cells.find(c => c[0] === 'tok')?.[1]).toBe('87k')
  expect(cells.find(c => c[0] === 'cost')?.[1]).toBe('$4.20')
  expect(statusOf(snap())).toContain('Relay | ctx 42% 84k/200k | 5h 31% ~2h10m')
})

test('no plan limits says so instead of inventing numbers', async () => {
  const s = snap({ limits: [] })
  expect(cellsOf(s).find(c => c[0] === 'quota')?.[1]).toBe('n/a')
  expect(sabhaLimitsOf(s.limits, NOW)).toBe('')
})

test('burn rate is points per hour since the session started', async () => {
  const s = snap()
  expect(burnOf(s.limits[0], s)).toBe(5)
  expect(burnOf(s.limits[0], snap({ startedAt: NOW }))).toBe(null)
})

test('pane lists every section and the cache reads apart', async () => {
  const titles = paneOf(snap()).map(([t]) => t)
  expect(titles).toEqual(['Session', 'Context', 'Quota', 'Agents', 'Tokens', 'Cost'])
  const tokens = paneOf(snap()).find(([t]) => t === 'Tokens')?.[1] ?? []
  expect(tokens.find(r => r[0] === 'cache read')?.[1]).toBe('1.0M')
  expect(paneOf(snap({ main: ZERO, sub: ZERO }))[4][1][0][1]).toBe('0')
})

test('sabha files match statusline-sabha.sh', async () => {
  const s = snap()
  const lines = sabhaLimitsOf(s.limits, NOW).trim().split('\n')
  expect(lines.length).toBe(2)
  const [kind, pct, at, written] = lines[0].split(' ')
  expect(kind).toBe('five_hour')
  expect(pct).toBe('31')
  expect(Number(at)).toBe(Math.floor((NOW + 2 * 3_600_000 + 10 * 60_000) / 1000))
  expect(Number(written)).toBe(Math.floor(NOW / 1000))
  expect(sabhaFileOf('BuilderPrecise-2')).toBe('builderprecise-2')
  expect(sabhaFileOf('Doctor Strange')).toBe('doctor-strange')
})
