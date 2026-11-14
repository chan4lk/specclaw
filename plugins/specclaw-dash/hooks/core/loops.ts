// The build, review and learning loops from a change folder's files: pure, over text the mod read.
// Plugins install into separate folders, so these small parsers are dash's own (not imports of core's).
import type { ChangeRow, FleetLine, LessonRow, ReviewRow, Section } from '../../types/index.d.ts'

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown) => (typeof v === 'string' && v !== '' ? v : null)
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0)
const json = (text: string) => {
  try {
    return JSON.parse(text) as unknown
  } catch {
    return undefined
  }
}
const jsonLines = (text: string) => text.split('\n').map(json).filter(isObject)

const TASK_LINE = /^\s*- \[(.)\] `T\d+`/gm
const leanTasks = (text: string) => {
  const start = text.search(/^## Tasks\s*$/m)
  if (start < 0) return ''
  const rest = text.slice(start + 1)
  const end = rest.search(/^## /m)
  return end < 0 ? rest : rest.slice(0, end)
}
const countTasks = (text: string) => {
  const marks = [...text.matchAll(TASK_LINE)].map(m => m[1])
  return { done: marks.filter(m => m?.toLowerCase() === 'x').length, total: marks.length, failed: marks.filter(m => m === '!').length }
}

// The latest span that started and has not stopped.
export const openSpan = (timeline: string): ChangeRow['span'] => {
  const open = new Map<string, { label: string; since: number }>()
  for (const line of jsonLines(timeline)) {
    const span = str(line.span)
    if (span === null) continue
    if (line.ev === 'start') {
      const since = typeof line.ts === 'number' ? line.ts * 1000 : Date.parse(String(line.at))
      if (Number.isFinite(since)) open.set(span, { label: str(line.label) ?? span, since })
    } else if (line.ev === 'stop') open.delete(span)
  }
  return [...open.values()].reduce<ChangeRow['span']>((best, s) => (best === null || s.since >= best.since ? s : best), null)
}

export type ChangeFiles = { name: string; state?: string; tasks?: string; lean?: string; timeline?: string }

export const parseChange = (f: ChangeFiles): ChangeRow => {
  const doc = f.state === undefined ? {} : json(f.state)
  const state = isObject(doc) ? doc : undefined
  const phases = isObject(state?.phases) ? state.phases : {}
  const phase = state === undefined ? '?' : (state.phase === undefined ? 'proposal' : (str(state.phase) ?? '?'))
  const verify = isObject(phases.verify) ? phases.verify : {}
  const pr = isObject(phases.pr) ? phases.pr : {}
  return {
    name: f.name, phase, ...countTasks(f.tasks ?? leanTasks(f.lean ?? '')),
    verdict: str(verify.verdict), pr: str(pr.url) ?? str(state?.pr), span: openSpan(f.timeline ?? ''),
  }
}

export const lessons = (change: string, timeline: string): LessonRow[] =>
  jsonLines(timeline).filter(l => l.kind === 'lesson').map(l => ({
    change, category: str(l.category) ?? '?', priority: str(l.priority) ?? '?', detail: str(l.detail) ?? '', at: str(l.at) ?? '',
  }))

// One round file per entry; a round that does not parse throws, and the section shows an error line.
export const reviewRow = (name: string, rounds: { n: number; text: string }[], head: string | null): ReviewRow => {
  const docs = [...rounds].sort((a, b) => a.n - b.n).map(r => {
    const doc = json(r.text)
    if (!isObject(doc)) throw new Error(`${name}: review round ${r.n} unreadable`)
    return doc
  })
  const last = docs.at(-1) ?? {}
  const counts = isObject(last.counts) ? last.counts : {}
  const finalHead = str(docs.filter(d => d.final === true).at(-1)?.head)
  const escalated = Array.isArray(last.escalated) ? last.escalated.length : num(last.escalated)
  const atHead = head === null || finalHead === null ? null : head.startsWith(finalHead) || finalHead.startsWith(head)
  return { name, rounds: docs.length, status: str(last.status) ?? '?', blocker: num(counts.blocker), major: num(counts.major), minor: num(counts.minor), escalated, finalHead, atHead }
}

const FLEET_TOTALS = ['wall_s', 'jobs', 'agent_s', 'hosted_s', 'review_rounds', 'commits', 'cost_usd', 'running', 'prs_open', 'unknown']

export const parseFleet = (text: string | undefined): Section<FleetLine> => {
  if (text === undefined) return { kind: 'missing', card: 'fleet: no report. Install specclaw-fleet (/plugin install specclaw-fleet@chan4lk), then run specclaw-fleet report --save' }
  const doc = json(text)
  const totals = isObject(doc) && isObject(doc.totals) ? doc.totals : undefined
  // The same validity check as specclaw-fleet's hooks/core/report.ts parseReport (plugins cannot import each
  // other): rows a list, every total a number, wall_s and cost_usd also allowed to be null.
  if (!isObject(doc) || doc.version !== 1 || !Array.isArray(doc.rows) || typeof doc.generated_at !== 'string'
    || Number.isNaN(Date.parse(doc.generated_at)) || totals === undefined
    || !FLEET_TOTALS.every(k => typeof totals[k] === 'number' || ((k === 'wall_s' || k === 'cost_usd') && totals[k] === null))) {
    return { kind: 'error', error: 'fleet report unreadable' }
  }
  return { kind: 'ok', data: { running: num(totals.running), prs_open: num(totals.prs_open), jobs: num(totals.jobs), generated_at: doc.generated_at } }
}

// specclaw-review's `learn_propose` answers `N proposed rule(s) …` or `no recurring lessons …`.
export const proposedCount = (text: string) => {
  const m = /^(\d+) proposed rule/.exec(text)
  if (m) return Number(m[1])
  if (text.startsWith('no recurring lessons')) return 0
  throw new Error('learn_propose answered in an unknown form')
}

const join = (base: string, rel: string) => {
  const parts: string[] = []
  for (const p of (rel.startsWith('/') ? rel : `${base}/${rel}`).split('/')) {
    if (p === '..') parts.pop()
    else if (p !== '' && p !== '.') parts.push(p)
  }
  return `/${parts.join('/')}`
}

// HEAD from files alone: `.git` as a folder or a `gitdir:` file (worktree, with `commondir`), then the loose
// ref, then `packed-refs`. `read` answers undefined for a missing file or a folder.
export const resolveHead = async (read: (path: string) => Promise<string | undefined>, cwd: string) => {
  const dotgit = await read(`${cwd}/.git`)
  const gitdir = dotgit?.startsWith('gitdir:') ? join(cwd, dotgit.slice(7).trim()) : `${cwd}/.git`
  const head = (await read(`${gitdir}/HEAD`))?.trim()
  if (!head) return null
  if (!head.startsWith('ref:')) return head
  const ref = head.slice(4).trim()
  const common = (await read(`${gitdir}/commondir`))?.trim()
  for (const dir of common ? [gitdir, join(gitdir, common)] : [gitdir]) {
    const loose = (await read(`${dir}/${ref}`))?.trim()
    if (loose) return loose
    const packed = (await read(`${dir}/packed-refs`))?.split('\n').find(l => l.endsWith(` ${ref}`))
    if (packed) return packed.split(' ')[0] ?? null
  }
  return null
}
