// The transcript scanner, ported from TBML scripts/dev_loop/dashboard/scan.py and spend.py.
// Kept: counts, times, ids, model names, titles and agent types. Never prompt, tool input or output,
// or thinking text: a record's content is read only to find its usage, and nothing of it is stored.
import type { Spend, TokenData, TokenRow } from '../../types/index.d.ts'

export const CONTEXT_WINDOW = 1_000_000

// $ per million tokens: input, output, cache read (claude-api skill, cached 2026-11-03). A cache write
// costs 1.25x input (5 minutes) or 2x (1 hour). An unlisted model costs as the dearest.
const PRICES: [string, [number, number, number]][] = [
  ['claude-opus-5-5', [4, 20, 0.2]],
  ['claude-opus-5', [5, 25, 0.5]],
  ['claude-sonnet-5-5', [2, 10, 0.1]],
  ['claude-sonnet-5', [2, 10, 0.2]],
  ['claude-fable-5-2', [8, 40, 0.2]],
  ['claude-fable-5-1', [10, 50, 0.25]],
  ['claude-haiku-5-5', [0.1, 0.5, 0.01]],
]
const DEAREST: [number, number, number] = [10, 50, 0.25]

// Longest id first, so `claude-opus-5-5[1m]` is opus-5-5 and not opus-5.
const BY_LENGTH = [...PRICES].sort((a, b) => b[0].length - a[0].length)
export const priceOf = (model: string) => BY_LENGTH.find(([id]) => model.startsWith(id))?.[1] ?? DEAREST

export type Call = { at: number; model: string; input: number; output: number; write5m: number; write1h: number; read: number }

export const usd = (c: Call) => {
  const [pin, pout, pread] = priceOf(c.model)
  return (pin * (c.input + c.write5m * 1.25 + c.write1h * 2) + pout * c.output + pread * c.read) / 1e6
}
export const contextOf = (c: Call) => c.input + c.write5m + c.write1h + c.read
const tokensOf = (c: Call) => contextOf(c) + c.output

export type FileScan = {
  size: number
  mtimeMs: number
  offset: number // characters of the text parsed so far: always just after a newline
  calls: Record<string, Call> // by message id: a message streamed in several records counts once
  context: number
  titles: { custom: string | null; ai: string | null }
  title: string | null
  branch: string | null
  unreadable: number
}

const fresh = (): FileScan => ({ size: 0, mtimeMs: 0, offset: 0, calls: {}, context: 0, titles: { custom: null, ai: null }, title: null, branch: null, unreadable: 0 })

export const needsRead = (prev: FileScan | undefined, size: number, mtimeMs: number) =>
  prev === undefined || prev.size !== size || prev.mtimeMs !== mtimeMs

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const count = (v: unknown, optional: boolean) => {
  if ((v === undefined || v === null) && optional) return 0
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0) throw new TypeError('a usage count is not a whole number')
  return v
}

const callOf = (record: Record<string, unknown>): [string, Call] => {
  const message = record.message as Record<string, unknown>
  const usage = message.usage as Record<string, unknown>
  if (!isObject(usage) || typeof message.model !== 'string') throw new TypeError('no usage or no model')
  const written = count(usage.cache_creation_input_tokens, true)
  const hour = count(isObject(usage.cache_creation) ? usage.cache_creation.ephemeral_1h_input_tokens : 0, true)
  const at = Date.parse(String(record.timestamp))
  if (Number.isNaN(at) || hour > written) throw new TypeError('bad time or cache split')
  const id = typeof message.id === 'string' ? message.id : String(record.uuid)
  return [id, { at, model: message.model, input: count(usage.input_tokens, false), output: count(usage.output_tokens, false),
    write5m: written - hour, write1h: hour, read: count(usage.cache_read_input_tokens, true) }]
}

// Apply one record; it throws before changing anything.
const apply = (scan: FileScan, record: Record<string, unknown>) => {
  const kind = record.type
  if (kind === 'custom-title' || kind === 'ai-title') {
    const name = record[kind === 'custom-title' ? 'customTitle' : 'aiTitle']
    if (typeof name !== 'string' || name === '') throw new TypeError('a session title is not a name')
    scan.titles[kind === 'custom-title' ? 'custom' : 'ai'] = name
    return
  }
  if (kind !== 'assistant' || !isObject(record.message) || !('usage' in record.message)) return
  const [id, call] = callOf(record)
  scan.calls[id] = call
  scan.context = contextOf(call) || scan.context
  if (typeof record.gitBranch === 'string' && record.gitBranch) scan.branch = record.gitBranch
}

const USAGE = '"usage":{'
const TITLE = 'Title":'

// Parse the complete lines after `prev.offset`; a shorter file, or no previous scan, starts over.
export const scanText = (prev: FileScan | undefined, text: string, size: number, mtimeMs: number): FileScan => {
  const resume = prev !== undefined && size >= prev.size && prev.offset <= text.length
  const scan: FileScan = resume ? { ...prev, calls: { ...prev.calls }, titles: { ...prev.titles } } : fresh()
  const end = text.lastIndexOf('\n') + 1
  if (end > scan.offset) {
    for (const raw of text.slice(scan.offset, end).split('\n')) {
      if (!raw.includes(USAGE) && !raw.includes(TITLE)) continue
      try {
        const record = JSON.parse(raw)
        if (isObject(record)) apply(scan, record)
        else scan.unreadable += 1
      } catch {
        scan.unreadable += 1
      }
    }
    scan.offset = end
  }
  scan.title = scan.titles.custom ?? scan.titles.ai
  return { ...scan, size, mtimeMs }
}

export type Transcript = { path: string; session: string; agent: string | null; role: string | null; scan: FileScan }

const add = (s: Spend, c: Call) => ({ tokens: s.tokens + tokensOf(c), usd: s.usd + usd(c) })
const ZERO: Spend = { tokens: 0, usd: 0 }
const top = (rows: TokenRow[], n: number) => [...rows].sort((a, b) => b.usd - a.usd).slice(0, n)

// Sum the scans. A message id counts once in today's and the week's totals (a forked session copies
// earlier messages, ids and all); each session still counts its own copy in its own spend.
export const summarize = (transcripts: Transcript[], dayStart: number, n = 5): Omit<TokenData, 'files' | 'skipped'> => {
  let today = ZERO, week = ZERO, unreadable = 0
  const seen = new Set<string>()
  const sessions = new Map<string, TokenRow>(), roles = new Map<string, TokenRow>()
  for (const t of transcripts) {
    unreadable += t.scan.unreadable
    const session = sessions.get(t.session) ?? { name: t.session, tokens: 0, usd: 0, context: null }
    const roleName = t.agent === null ? 'main' : (t.role ?? 'subagent')
    const role = roles.get(roleName) ?? { name: roleName, tokens: 0, usd: 0, context: null }
    for (const [id, call] of Object.entries(t.scan.calls)) {
      Object.assign(session, add(session, call))
      Object.assign(role, add(role, call))
      if (seen.has(id)) continue
      seen.add(id)
      week = add(week, call)
      if (call.at >= dayStart) today = add(today, call)
    }
    if (t.agent === null) {
      session.name = t.scan.title ?? t.scan.branch ?? t.session.slice(0, 8)
      session.context = t.scan.context
    }
    sessions.set(t.session, session)
    roles.set(roleName, role)
  }
  return { today, week, sessions: top([...sessions.values()], n), roles: top([...roles.values()], n), unreadable }
}

// Claude Code's folder for a project: the path with every non-alphanumeric character as `-`.
export const encodeProject = (cwd: string) => cwd.replace(/[^a-zA-Z0-9]/g, '-')
