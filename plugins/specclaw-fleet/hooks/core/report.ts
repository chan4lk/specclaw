import type { FleetRow as Row, FleetTotals as Totals, FleetView as View } from '../../types/index.d.ts'

export type { Row, Totals, View }
export type Report = Extract<View, { kind: 'report' }>['report']

const TEXT = ['state', 'exit', 'queued', 'dispatched', 'finished', 'phase', 'agent_started', 'agent_ended', 'pr', 'pr_status', 'pr_opened', 'pr_closed', 'note'] as const
const NUM = ['wave', 'agent_s', 'review_rounds', 'agent_commits', 'cost_usd'] as const
const TOTALS = ['wall_s', 'jobs', 'agent_s', 'hosted_s', 'review_rounds', 'commits', 'cost_usd', 'running', 'prs_open'] as const

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown) => (typeof v === 'string' && v !== '' ? v : null)
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)

const row = (raw: Record<string, unknown>): Row => {
  const out = { change: String(raw.change) } as Record<string, unknown>
  for (const key of TEXT) out[key] = str(raw[key])
  for (const key of NUM) out[key] = num(raw[key])
  return out as Row
}

export const parseReport = (text: string | undefined): View => {
  if (text === undefined) return { kind: 'none' }
  let doc: unknown
  try {
    doc = JSON.parse(text)
  } catch {
    return { kind: 'unreadable' }
  }
  if (!isObject(doc) || doc.version !== 1 || typeof doc.generated_at !== 'string' || Number.isNaN(Date.parse(doc.generated_at)) || !Array.isArray(doc.rows) || !isObject(doc.totals)) return { kind: 'unreadable' }
  const rows = doc.rows.filter(isObject).filter(r => typeof r.change === 'string').map(row)
  const totals = Object.fromEntries(TOTALS.map(key => [key, num((doc.totals as Record<string, unknown>)[key])]))
  for (const key of ['jobs', 'agent_s', 'hosted_s', 'review_rounds', 'commits', 'running', 'prs_open']) totals[key] ??= 0
  return { kind: 'report', report: { generated_at: doc.generated_at, scope: String(doc.scope ?? 'latest'), rows, totals: totals as Totals } }
}
