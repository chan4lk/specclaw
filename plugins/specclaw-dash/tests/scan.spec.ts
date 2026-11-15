import { expect, test } from 'bun:test'
import { encodeProject, needsRead, priceOf, scanText, summarize, usd, type Transcript } from '../hooks/core/scan.ts'
import { NOW, assistant, lines, title, toolResult, user } from './fixtures.ts'

const DAY = Date.parse('2026-11-14T00:00:00Z')
const bytes = (s: string) => new TextEncoder().encode(s).length

test('R062 AC-2 cost: list price, 5-minute write 1.25x, 1-hour write 2x, cache read', () => {
  const call = { at: 0, model: 'claude-opus-5-5', input: 1000, output: 2000, write5m: 4000, write1h: 1000, read: 10000 }
  expect(usd(call)).toBeCloseTo(0.074, 10)
  expect(usd({ ...call, model: 'claude-sonnet-5-5' })).toBeCloseTo((2 * 8000 + 10 * 2000 + 0.1 * 10000) / 1e6, 10)
})

test('R062 AC-2 a suffixed id prices as its model; an unknown model as the dearest', () => {
  expect(priceOf('claude-opus-5-5[1m]')).toEqual(priceOf('claude-opus-5-5'))
  expect(priceOf('claude-opus-5')).toEqual([5, 25, 0.5])
  expect(priceOf('mystery')).toEqual(priceOf('claude-fable-5-1'))
})

test('R062 AC-2 a scan keeps counts, model, title and branch, and no prompt, tool or thinking text', () => {
  const text = lines(user(), title('ai-title', 'old name'), assistant('m1', '2026-11-14T10:00:00Z', { input: 10, output: 20, write: 30, hour: 10, read: 40 }),
    toolResult(), title('custom-title', 'Build 062'), assistant('m2', '2026-11-14T10:01:00Z', { input: 1, output: 2, read: 7 }))
  const scan = scanText(undefined, text, bytes(text), 1)
  expect(Object.keys(scan.calls)).toEqual(['m1', 'm2'])
  expect(scan.calls.m1).toEqual({ at: Date.parse('2026-11-14T10:00:00Z'), model: 'claude-opus-5-5', input: 10, output: 20, write5m: 20, write1h: 10, read: 40 })
  expect([scan.title, scan.branch, scan.context, scan.unreadable]).toEqual(['Build 062', 'claude/x', 8, 0])
  expect(JSON.stringify(scan)).not.toMatch(/SECRET/)
})

test('R062 AC-2 a message streamed in several records counts once, at its last record', () => {
  const text = lines(assistant('m1', '2026-11-14T10:00:00Z', { output: 1 }), assistant('m1', '2026-11-14T10:00:05Z', { output: 50 }))
  expect(scanText(undefined, text, bytes(text), 1).calls.m1?.output).toBe(50)
})

test('R062 AC-3 a grown file is parsed from its offset, a half line waits', () => {
  const first = lines(assistant('m1', '2026-11-14T10:00:00Z', { output: 1 }))
  const half = assistant('m2', '2026-11-14T10:01:00Z', { output: 2 })
  const a = scanText(undefined, first + half.slice(0, 40), bytes(first) + 40, 1)
  expect([Object.keys(a.calls), a.offset]).toEqual([['m1'], first.length])
  // The earlier line is replaced with junk: parsing from the offset never sees it.
  const grown = 'x'.repeat(first.length) + lines(half)
  const b = scanText(a, grown, bytes(grown), 2)
  expect([Object.keys(b.calls), b.unreadable, b.offset]).toEqual([['m1', 'm2'], 0, grown.length])
})

test('R062 AC-3 a shorter file is parsed again from the start', () => {
  const big = lines(assistant('m1', '2026-11-14T10:00:00Z', { output: 1 }), assistant('m2', '2026-11-14T10:00:00Z', { output: 1 }))
  const small = lines(assistant('m3', '2026-11-14T10:00:00Z', { output: 3 }))
  const b = scanText(scanText(undefined, big, bytes(big), 1), small, bytes(small), 2)
  expect(Object.keys(b.calls)).toEqual(['m3'])
})

test('R062 AC-3 unchanged size and mtime need no read', () => {
  const s = scanText(undefined, '', 0, 5)
  expect([needsRead(undefined, 0, 5), needsRead(s, 0, 5), needsRead(s, 10, 5), needsRead(s, 0, 6)]).toEqual([true, false, true, true])
})

test('R062 AC-3 bad records are counted, never guessed at', () => {
  const bad = [
    '{"type":"assistant","message":{"usage":{"input_tokens":1}', // not JSON
    assistant('m1', '2026-11-14T10:00:00Z', { input: -1 }),
    assistant('m2', 'not a time', { input: 1 }),
    JSON.stringify({ type: 'assistant', timestamp: '2026-11-14T10:00:00Z', message: { id: 'm3', model: 7, usage: { input_tokens: 1, output_tokens: 1 } } }),
    JSON.stringify({ type: 'assistant', timestamp: '2026-11-14T10:00:00Z', message: { id: 'm4', model: 'claude-opus-5-5', usage: { input_tokens: 1.5, output_tokens: 1 } } }),
    title('custom-title', ''),
  ]
  const text = lines(...bad)
  const s = scanText(undefined, text, bytes(text), 1)
  expect([Object.keys(s.calls), s.unreadable]).toEqual([[], 6])
})

const t = (path: string, session: string, agent: string | null, role: string | null, text: string): Transcript =>
  ({ path, session, agent, role, scan: scanText(undefined, text, bytes(text), 1) })

test('R062 AC-2 summary: today once per message id, sessions with their subagents, cost by role, nothing before the week', () => {
  const main = lines(assistant('ancient', '2026-11-01T09:00:00Z', { input: 9000, output: 9000 }), title('custom-title', 'Build 062'), assistant('a', '2026-11-14T09:00:00Z', { input: 1000, output: 1000 }),
    assistant('old', '2026-11-13T09:00:00Z', { input: 1000 }))
  const fork = lines(assistant('a', '2026-11-14T09:00:00Z', { input: 1000, output: 1000 }))
  const sub = lines(assistant('s1', '2026-11-14T09:30:00Z', { output: 1000, read: 5000 }, 'claude-sonnet-5-5'))
  const sum = summarize([
    t('/p/s1.jsonl', 's1', null, null, main),
    t('/p/s2.jsonl', 's2', null, null, fork),
    t('/p/s1/subagents/agent-x.jsonl', 's1', 'x', 'code-reviewer', sub),
  ], DAY, DAY - 6 * 86400 * 1000)
  const a = (4 * 1000 + 20 * 1000) / 1e6, old = 4 * 1000 / 1e6, s1 = (10 * 1000 + 0.1 * 5000) / 1e6
  expect(sum.today.usd).toBeCloseTo(a + s1, 10)
  expect(sum.today.tokens).toBe(2000 + 6000)
  expect(sum.week.usd).toBeCloseTo(a + old + s1, 10)
  expect(sum.sessions.map(s => [s.name, Number(s.usd.toFixed(6)), s.context])).toEqual([
    ['Build 062', Number((a + old + s1).toFixed(6)), 1000],
    ['claude/x', Number(a.toFixed(6)), 1000],
  ])
  expect(sum.roles.map(r => [r.name, Number(r.usd.toFixed(6))])).toEqual([['main', Number((2 * a + old).toFixed(6))], ['code-reviewer', Number(s1.toFixed(6))]])
  expect(sum.unreadable).toBe(0)
})

test('R062 AC-2 the project folder name replaces every non-alphanumeric character', () => {
  expect(encodeProject('/Users/me/repos/spec.claw_x')).toBe('-Users-me-repos-spec-claw-x')
  expect(NOW).toBeGreaterThan(DAY)
})
