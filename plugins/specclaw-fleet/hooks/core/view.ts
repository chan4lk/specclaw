import type { Report, Row, View } from './report.ts'

const ms = (iso: string | null) => (iso ? Date.parse(iso) : NaN)
const LIVE = new Set(['dispatched', 'running'])
export const running = (rows: Row[]) => rows.filter(r => LIVE.has(r.state ?? '')).length

export const dur = (s: number | null) => {
  if (s === null) return '-'
  const m = Math.floor(s / 60)
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`
}

const hhmm = (t: number) => new Date(t).toISOString().slice(11, 16)
const lastRun = (rows: Row[]) => {
  const times = rows.flatMap(r => [ms(r.dispatched), ms(r.agent_started)]).filter(Number.isFinite)
  return times.length ? ` · last run ${hhmm(Math.max(...times))} UTC` : ''
}

const unknown = (r: Report) => (r.totals.unknown > 0 ? ` · ${r.totals.unknown} unknown` : '')
const stale = (r: Report, now: number) => {
  const s = (now - ms(r.generated_at)) / 1000
  return s >= 3600 ? ` · snapshot ${age(s)}` : ''
}
export const bandText = (view: View, now: number) => {
  if (view.kind === 'none') return undefined
  if (view.kind === 'unreadable') return 'fleet · report unreadable'
  const { rows, totals } = view.report
  return `fleet · ${running(rows)} running · ${totals.prs_open} PRs open${unknown(view.report)}${lastRun(rows)}${stale(view.report, now)}`
}

export const statusText = (view: View, now: number) =>
  view.kind === 'none' ? undefined : view.kind === 'unreadable' ? 'fleet: report unreadable' : `fleet: ${running(view.report.rows)} running${unknown(view.report)}${stale(view.report, now)}`

const spans = (r: Row, now: number): [number, number, string][] => [
  [ms(r.queued ?? r.dispatched), ms(r.finished), '░'],
  [ms(r.pr_opened), ms(r.pr_closed) || (r.pr_status === 'active' ? now : NaN), '▒'],
  [ms(r.agent_started), ms(r.agent_ended) || (LIVE.has(r.state ?? '') ? now : NaN), '█'],
]

export const timeline = (rows: Row[], now: number, width: number) => {
  const all = rows.flatMap(r => spans(r, now).flatMap(([a, b]) => [a, b])).filter(Number.isFinite)
  if (all.length === 0) return rows.map(() => '·'.repeat(width))
  const t0 = Math.min(...all), t1 = Math.max(...all, t0 + 1)
  const col = (t: number) => Math.min(width - 1, Math.floor(((t - t0) / (t1 - t0)) * width))
  return rows.map(r => {
    const cells = Array<string>(width).fill('·')
    for (const [a, b, mark] of spans(r, now)) {
      if (!Number.isFinite(a)) continue
      for (let i = col(a); i <= col(Number.isFinite(b) ? b : a); i++) cells[i] = mark
    }
    return cells.join('')
  })
}

const age = (s: number) => (s < 60 ? 'just now' : s < 3600 ? `${Math.floor(s / 60)}m old` : s < 86400 ? `${Math.floor(s / 3600)}h old` : `${Math.floor(s / 86400)}d old`)
const pad = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + '…' : s.padEnd(n))
const cost = (r: Report) => (r.totals.cost_usd === null ? '-' : `$${r.totals.cost_usd.toFixed(2)}`)

export const paneLines = (view: View, now: number, columns = 100) => {
  if (view.kind === 'none') return ['No fleet report yet.', 'Refresh: specclaw-fleet report --save']
  if (view.kind === 'unreadable') return ['fleet · report unreadable', 'Refresh: specclaw-fleet report --save']
  const r = view.report, t = r.totals, name = 24
  const rows = [...r.rows].sort((a, b) => (a.wave ?? 0) - (b.wave ?? 0) || a.change.localeCompare(b.change))
  const bars = timeline(rows, now, Math.max(10, Math.min(60, columns - name - 4)))
  const table = rows.map(x => [pad(x.change, name), pad(x.wave === null ? '-' : String(x.wave), 4), pad(x.state ?? '-', 10), pad(dur(x.agent_s), 7),
    pad(x.review_rounds === null ? '-' : String(x.review_rounds), 6), x.pr ? `#${x.pr.split('/').pop()} ${x.pr_status ?? '?'}` : '-'].join(' '))
  return [
    `fleet build · ${r.scope} · snapshot ${age(Math.max(0, (now - ms(r.generated_at)) / 1000))}`,
    `wall ${dur(t.wall_s)} · ${t.jobs} jobs · agent ${dur(t.agent_s)} · hosted ${dur(t.hosted_s)} · ${t.review_rounds} rounds · ${t.commits} commits`,
    `${running(r.rows)} running · ${t.prs_open} PRs open${unknown(r)} · cost ${cost(r)} (API-equivalent estimate)`,
    '',
    ...rows.map((x, i) => `${pad(x.change, name)} ${bars[i]}`),
    `${' '.repeat(name)} ░ pipeline  █ agent  ▒ PR open`,
    '',
    `${pad('CHANGE', name)} ${pad('WAVE', 4)} ${pad('STATE', 10)} ${pad('AGENT', 7)} ${pad('ROUNDS', 6)} PR`,
    ...table,
    '',
    'Refresh: specclaw-fleet report --save',
  ]
}
