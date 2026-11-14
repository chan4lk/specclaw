// Every read the pane makes, through $.fs, $.env and one MCP call. It never writes and never runs a command.
import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { BuildData, ChangeRow, DashView, LearningData, LessonRow, ReviewRow, Section, TokenData } from '../types/index.d.ts'
import { lessons, parseChange, parseFleet, proposedCount, resolveHead, reviewRow } from './core/loops.ts'
import { encodeProject, needsRead, scanText, summarize, type FileScan, type Transcript } from './core/scan.ts'
import { statusText } from './core/view.ts'

const NOTHING: Section<never> = { kind: 'missing', card: 'Not read yet.' }
const EMPTY: DashView = { at: 0, build: NOTHING, review: NOTHING, learning: NOTHING, tokens: NOTHING }
const view = atom({ plugin: 'specclaw-dash', key: 'view' } as const, EMPTY, { shape: 'dash-view-1' })

const MAX_READ = 4 * 1024 * 1024 // $.fs.read refuses more
const WEEK = 7 * 86400 * 1000
const CHANGE_DIR = /^\d{3}-/
const ROUND = /^round-(\d+)\.json$/
const REVIEW_MCP = 'plugin:specclaw-review:specclaw-review'

// The scan state: a reload starts it over, which is a full rescan.
const scans = new Map<string, FileScan>()
const roles = new Map<string, string | null>()

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

async function text($: EngineInterface, path: string) {
  if (!(await $.fs.exists(path))) return undefined
  const value = await $.fs.read(path)
  if (typeof value !== 'string') throw new Error(`${path} is not text`)
  return value
}
async function quietText($: EngineInterface, path: string) {
  return text($, path).catch(() => undefined)
}

type ChangeRead = { row: ChangeRow; rounds: { n: number; text: string }[]; lessons: LessonRow[] }

async function readChange($: EngineInterface, root: string, name: string): Promise<ChangeRead> {
  const dir = `${root}/${name}`
  const timeline = await text($, `${dir}/timeline.jsonl`)
  const row = parseChange({ name, state: await text($, `${dir}/state.json`), tasks: await text($, `${dir}/tasks.md`), lean: await text($, `${dir}/change.md`), timeline })
  const entries = (await $.fs.exists(`${dir}/review`)) ? await $.fs.list(`${dir}/review`) : []
  const rounds = await Promise.all(entries.flatMap(e => {
    const m = e.kind === 'file' ? ROUND.exec(e.name) : null
    return m ? [text($, `${dir}/review/${e.name}`).then(t => ({ n: Number(m[1]), text: t ?? '' }))] : []
  }))
  return { row, rounds, lessons: lessons(name, timeline ?? '') }
}

async function proposed($: EngineInterface): Promise<Section<number>> {
  let answer: string
  try {
    const link = await $.mcp.connect(REVIEW_MCP)
    if (!link.isConnected && link.reason === 'unlisted') {
      return { kind: 'missing', card: 'Proposed rules: specclaw-review is not installed. Install: /plugin install specclaw-review@chan4lk' }
    }
    if (!link.isConnected) return { kind: 'error', error: `specclaw-review not connected (${link.reason}): ${link.message}` }
    const result = await $.mcp.call(link.server, 'learn_propose')
    const first = result.content.find(b => b.type === 'text')
    answer = first?.text ?? ''
    if (result.isError) return { kind: 'error', error: `learn_propose failed: ${answer.split('\n')[0]}` }
  } catch (error) {
    return { kind: 'error', error: `learn_propose failed: ${message(error)}` }
  }
  try {
    return { kind: 'ok', data: proposedCount(answer) }
  } catch (error) {
    return { kind: 'error', error: message(error) }
  }
}

async function readLoops($: EngineInterface, cwd: string): Promise<Pick<DashView, 'build' | 'review' | 'learning'>> {
  if (!(await $.fs.exists(`${cwd}/.specclaw`))) {
    const card = 'No .specclaw/ in this project. Install specclaw: /plugin install specclaw@chan4lk'
    return { build: { kind: 'missing', card }, review: { kind: 'missing', card }, learning: { kind: 'missing', card } }
  }
  const root = `${cwd}/.specclaw/changes`
  const names = (await $.fs.exists(root)) ? (await $.fs.list(root)).filter(e => e.kind === 'dir' && CHANGE_DIR.test(e.name)).map(e => e.name).sort() : []
  const changes = (await Promise.all(names.map(n => readChange($, root, n)))).filter(c => c.row.phase !== 'archived')
  const fleet = parseFleet(await text($, `${cwd}/.specclaw/fleet/report.json`).catch(() => '{'))
  const build: BuildData = { changes: changes.map(c => c.row), fleet }

  const rules = await proposed($)
  const reviewed = changes.filter(c => c.rounds.length > 0)
  let review: Section<ReviewRow[]>
  if (reviewed.length === 0 && rules.kind === 'missing') review = { kind: 'missing', card: 'Review loop: no rounds yet. Install specclaw-review: /plugin install specclaw-review@chan4lk' }
  else {
    const head = reviewed.length ? await resolveHead(path => quietText($, path), cwd) : null
    try {
      review = { kind: 'ok', data: reviewed.map(c => reviewRow(c.row.name, c.rounds, head)) }
    } catch (error) {
      review = { kind: 'error', error: message(error) }
    }
  }
  const all = changes.flatMap(c => c.lessons).sort((a, b) => a.at.localeCompare(b.at))
  const byCategory: Record<string, number> = {}
  for (const l of all) byCategory[l.category] = (byCategory[l.category] ?? 0) + 1
  const learning: LearningData = { lessons: all, byCategory, proposed: rules }
  return { build: { kind: 'ok', data: build }, review, learning: { kind: 'ok', data: learning } }
}

async function role($: EngineInterface, path: string) {
  if (!roles.has(path)) {
    const meta = await text($, path.replace(/\.jsonl$/, '.meta.json')).catch(() => undefined)
    let type: string | null = null
    try {
      const doc = meta === undefined ? undefined : JSON.parse(meta)
      if (typeof doc?.agentType === 'string') type = doc.agentType
    } catch { /* a bad meta: the agent is "subagent" */ }
    roles.set(path, type)
  }
  return roles.get(path) ?? null
}

async function readTokens($: EngineInterface, cwd: string, now: number): Promise<Section<TokenData>> {
  const base = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? `${await $.env.get('HOME')}/.claude`
  const dir = `${base}/projects/${encodeProject(cwd)}`
  if (!(await $.fs.exists(dir))) return { kind: 'missing', card: `No Claude Code transcripts at ${dir}` }
  const found: { path: string; size: number; mtimeMs: number; session: string; agent: string | null }[] = []
  for (const e of await $.fs.list(dir)) {
    if (e.kind === 'file' && e.name.endsWith('.jsonl')) found.push({ path: `${dir}/${e.name}`, size: e.size, mtimeMs: e.mtimeMs, session: e.name.slice(0, -6), agent: null })
    if (e.kind !== 'dir' || !(await $.fs.exists(`${dir}/${e.name}/subagents`))) continue
    for (const a of await $.fs.list(`${dir}/${e.name}/subagents`)) {
      if (a.kind === 'file' && a.name.startsWith('agent-') && a.name.endsWith('.jsonl'))
        found.push({ path: `${dir}/${e.name}/subagents/${a.name}`, size: a.size, mtimeMs: a.mtimeMs, session: e.name, agent: a.name.slice(6, -6) })
    }
  }
  const recent = found.filter(f => f.mtimeMs >= now - WEEK)
  const kept = new Set(recent.map(f => f.path))
  for (const path of scans.keys()) if (!kept.has(path)) scans.delete(path)
  let skipped = 0
  const transcripts: Transcript[] = []
  for (const f of recent) {
    // shortcut: a transcript over 4 MiB cannot be read by a mod, so it is counted as skipped and the totals
    // show ≥; upgrade when $.fs.read takes a byte range.
    if (f.size > MAX_READ) {
      skipped += 1
      scans.delete(f.path)
      continue
    }
    try {
      const prev = scans.get(f.path)
      const scan = needsRead(prev, f.size, f.mtimeMs) ? scanText(prev, await $.fs.read(f.path), f.size, f.mtimeMs) : prev!
      scans.set(f.path, scan)
      transcripts.push({ path: f.path, session: f.session, agent: f.agent, role: f.agent === null ? null : await role($, f.path), scan })
    } catch {
      skipped += 1 // removed or unreadable since the listing: left out, and the totals say ≥
      scans.delete(f.path)
    }
  }
  const day = new Date(now)
  const dayStart = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate())
  return { kind: 'ok', data: { ...summarize(transcripts, dayStart, now - WEEK), files: recent.length, skipped } }
}

const failed = (error: unknown): Section<never> => ({ kind: 'error', error: message(error) })

export async function refresh($: EngineInterface) {
  const now = await $.clock.now()
  let next: DashView
  try {
    const cwd = await $.session.cwd()
    const loops = await readLoops($, cwd).catch(error => ({ build: failed(error), review: failed(error), learning: failed(error) }))
    next = { at: now, ...loops, tokens: await readTokens($, cwd, now).catch(failed) }
  } catch (error) {
    next = { at: now, build: failed(error), review: failed(error), learning: failed(error), tokens: failed(error) }
  }
  await update($, view, () => next)
  await Promise.resolve().then(() => $.ui.status(statusText(next))).catch(() => undefined)
}

export async function refreshQuietly($: EngineInterface) {
  await refresh($).catch(() => undefined)
}

export async function notify($: EngineInterface, text: string) {
  await Promise.resolve().then(() => $.ui.toast(text)).catch(() => undefined)
}

export async function readView($: EngineInterface) {
  return read($, view)
}
