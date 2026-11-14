import type { BuildData, DashView, LearningData, ReviewRow, Section, TokenData } from '../../types/index.d.ts'
import { CONTEXT_WINDOW } from './scan.ts'

export const LABEL = 'API-equivalent estimate'

const pad = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s.padEnd(n))
const hhmm = (t: number) => new Date(t).toISOString().slice(11, 16)
export const dur = (ms: number) => {
  const m = Math.max(0, Math.floor(ms / 60000))
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`
}
const age = (ms: number) => (ms < 60000 ? 'just now' : `${dur(ms)} old`)
export const tokens = (n: number) => (n >= 1e9 ? `${(n / 1e9).toFixed(1)}B` : n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : String(n))
const lowerBound = (t: TokenData) => (t.skipped > 0 ? '≥' : '')
export const money = (t: TokenData, usd: number) => `${lowerBound(t)}$${usd.toFixed(2)}`

// A section that is not ok draws one line: its install card or its error. Never its old numbers.
const other = <T>(s: Section<T>, indent = '  ') => (s.kind === 'missing' ? [`${indent}${s.card}`] : s.kind === 'error' ? [`${indent}error: ${s.error}`] : [])

const counts = (view: DashView) => {
  if (view.build.kind !== 'ok') return undefined
  const changes = view.build.data.changes
  return { building: changes.filter(c => c.phase === 'build').length, review: changes.filter(c => c.phase === 'verify').length }
}

const buildLines = (b: BuildData, now: number) => [
  ...(b.changes.length === 0 ? ['  No active changes.'] : b.changes.map(c => [
    `  ${pad(c.name, 28)}`, pad(c.phase, 8), `${c.done}/${c.total}${c.failed ? ` ✗${c.failed}` : ''}`.padEnd(8),
    c.span ? `${c.span.label} ${dur(now - c.span.since)}` : '', c.verdict ?? '', c.pr ? `PR ${c.pr.split('/').pop()}` : '',
  ].filter(Boolean).join(' '))),
  ...(b.fleet.kind === 'ok'
    ? [`  fleet · ${b.fleet.data.running} running · ${b.fleet.data.prs_open} PRs open · ${b.fleet.data.jobs} jobs · snapshot ${age(now - Date.parse(b.fleet.data.generated_at))}`]
    : other(b.fleet)),
]

const final = (r: ReviewRow) => (r.finalHead === null ? 'no final pass' : `final ${r.finalHead.slice(0, 10)}${r.atHead === null ? '' : r.atHead ? ' at HEAD' : ' behind HEAD'}`)
const reviewLines = (rows: ReviewRow[]) => rows.length === 0 ? ['  No review rounds in the active changes.'] : rows.map(r =>
  `  ${pad(r.name, 28)} ${r.rounds} rounds · ${r.status} · last ${r.blocker}/${r.major}/${r.minor} b/M/m · ${r.escalated} escalated · ${final(r)}`)

const learningLines = (l: LearningData) => [
  `  ${l.lessons.length} lessons${Object.entries(l.byCategory).map(([k, n]) => ` · ${k} ${n}`).join('')}`,
  ...l.lessons.slice(-3).map(x => `  ${pad(x.change, 28)} ${x.priority} ${x.category}: ${x.detail}`),
  ...(l.proposed.kind === 'ok' ? [`  ${l.proposed.data} proposed rules awaiting approval${l.proposed.data ? ' (specclaw-review learn)' : ''}`] : other(l.proposed)),
]

const tokenLines = (t: TokenData) => [
  `  today ${lowerBound(t)}${tokens(t.today.tokens)} tokens · ${money(t, t.today.usd)} · 7 days ${lowerBound(t)}${tokens(t.week.tokens)} tokens · ${money(t, t.week.usd)}`,
  ...t.sessions.map(s => `  ${pad(s.name, 28)} ${money(t, s.usd).padStart(9)}${s.context === null ? '' : ` · context ${Math.round((s.context / CONTEXT_WINDOW) * 100)}%`}`),
  `  by role: ${t.roles.map(r => `${r.name} ${money(t, r.usd)}`).join(' · ') || '-'}`,
  `  ${t.files} transcripts${t.skipped ? ` · ${t.skipped} over 4 MiB not counted (totals are a lower bound)` : ''}${t.unreadable ? ` · ${t.unreadable} unreadable records` : ''}`,
]

const section = <T>(title: string, s: Section<T>, draw: (d: T) => string[]) => [title, ...(s.kind === 'ok' ? draw(s.data) : other(s))]

export const paneLines = (view: DashView, now: number) => [
  `dash · read ${hhmm(view.at)} UTC · read only`,
  '',
  ...section('BUILD', view.build, d => buildLines(d, now)),
  '',
  ...section('REVIEW', view.review, reviewLines),
  '',
  ...section('LEARNING', view.learning, learningLines),
  '',
  ...section(`TOKENS · last 7 days · cost is an ${LABEL}`, view.tokens, tokenLines),
  '',
  'More: /specclaw-pane · /fleet-pane',
]

const todayCost = (view: DashView) => (view.tokens.kind === 'ok' ? `${money(view.tokens.data, view.tokens.data.today.usd)} today` : undefined)

export const bandText = (view: DashView) => {
  if (view.build.kind === 'missing') return undefined
  if (view.build.kind === 'error') return 'dash · could not read changes'
  const c = counts(view)!, cost = todayCost(view)
  return `dash · ${c.building} building · ${c.review} in review${cost ? ` · ${cost}, ${LABEL}` : ''}`
}

export const statusText = (view: DashView) => {
  if (view.build.kind === 'missing') return undefined
  if (view.build.kind === 'error') return 'dash: could not read changes'
  const cost = todayCost(view)
  return `dash: ${counts(view)!.building} building${cost ? ` · ${cost} (${LABEL})` : ''}`
}
