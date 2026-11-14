import { expect, test } from 'bun:test'
import { lessons, openSpan, parseChange, parseFleet, proposedCount, resolveHead, reviewRow } from '../hooks/core/loops.ts'

const TIMELINE = [
  '{"ev":"start","span":"plan","kind":"phase","label":"plan","at":"2026-11-14T04:49:49Z","ts":1794631789}',
  '{"ev":"stop","span":"plan","at":"2026-11-14T04:50:22Z","ts":1794631822,"status":"ok"}',
  '{"ev":"start","span":"W1","kind":"wave","label":"wave 1","at":"2026-11-14T04:50:43Z","ts":1794631843}',
  '{"kind":"lesson","at":"2026-11-14T05:00:00Z","category":"pattern","priority":"high","detail":"say hi","action":"do it"}',
  'not json',
  '{"kind":"lesson","at":"2026-11-14T06:00:00Z","category":"spec_gap","priority":"low","detail":"d2","action":"a"}',
].join('\n')

const STATE = JSON.stringify({ change: '062-x', phase: 'build', phases: { verify: { verdict: 'PASS' }, pr: { url: 'https://x/pull/9' } } })
const TASKS = '- [x] `T1` — a\n- [ ] `T2` — b\n- [!] `T3` — c\n'

test('R062 AC-4 a change row: phase, tasks, verdict, PR and the open span', () => {
  expect(parseChange({ name: '062-x', state: STATE, tasks: TASKS, timeline: TIMELINE })).toEqual({
    name: '062-x', phase: 'build', done: 1, total: 3, failed: 1, verdict: 'PASS', pr: 'https://x/pull/9',
    span: { label: 'wave 1', since: 1794631843000 },
  })
})

test('R062 AC-4 a change with no state is a proposal; unparseable state is "?"', () => {
  expect(parseChange({ name: 'a' }).phase).toBe('proposal')
  expect(parseChange({ name: 'a', state: '{nope' }).phase).toBe('?')
  expect(parseChange({ name: 'a', lean: '# X\n\n## Tasks\n\n- [x] `T1` — m\n\n## Verify\n- [ ] `T9` — not a task\n' })).toMatchObject({ done: 1, total: 1 })
})

test('R062 AC-4 every span stopped means no open span', () => {
  expect(openSpan(TIMELINE.split('\n').slice(0, 2).join('\n'))).toBeNull()
})

test('R062 AC-4 lesson lines, newest last; other lines are not lessons', () => {
  expect(lessons('062-x', TIMELINE).map(l => [l.category, l.priority, l.detail])).toEqual([['pattern', 'high', 'say hi'], ['spec_gap', 'low', 'd2']])
})

const round = (n: number, o: object) => ({ n, text: JSON.stringify({ round: n, status: 'findings', counts: { blocker: 0, major: 0, minor: 0 }, final: false, ...o }) })

test('R062 AC-4 review row: last round counts, escalations as a list or a number, final pass at HEAD', () => {
  const rounds = [
    round(10, { status: 'clean', final: true, head: 'abc1234', counts: { blocker: 0, major: 0, minor: 4 }, escalated: 0 }),
    round(9, { counts: { blocker: 1, major: 2, minor: 0 }, escalated: ['f1', 'f2'] }),
  ]
  expect(reviewRow('059-x', rounds, 'abc1234def')).toEqual({ name: '059-x', rounds: 2, status: 'clean', blocker: 0, major: 0, minor: 4, escalated: 0, finalHead: 'abc1234', atHead: true })
  expect(reviewRow('059-x', rounds.slice(1), 'abc')).toMatchObject({ blocker: 1, major: 2, escalated: 2, finalHead: null, atHead: null })
  expect(reviewRow('059-x', rounds, 'fff0000').atHead).toBe(false)
  expect(() => reviewRow('059-x', [{ n: 1, text: '{nope' }], null)).toThrow()
})

const TOTALS = { wall_s: null, jobs: 3, agent_s: 0, hosted_s: 0, review_rounds: 0, commits: 0, cost_usd: null, running: 2, prs_open: 1, unknown: 0 }
const report = (o: object = {}, totals: object = {}) => JSON.stringify({ version: 1, generated_at: '2026-11-14T11:58:00Z', rows: [], totals: { ...TOTALS, ...totals }, ...o })

test('R062 AC-5 fleet report: totals and missing', () => {
  expect(parseFleet(report())).toEqual({ kind: 'ok', data: { running: 2, prs_open: 1, jobs: 3, generated_at: '2026-11-14T11:58:00Z' } })
  expect(parseFleet(report({}, { wall_s: 60, cost_usd: 1.5 })).kind).toBe('ok')
  expect(parseFleet(undefined).kind).toBe('missing')
})

// The rows of specclaw-fleet's report.spec 'unreadable' cases, plus the ones its parser shares with dash.
const UNREADABLE: [string, string][] = [
  ['not JSON', '{nope'],
  ['wrong version', report({ version: 2 })],
  ['generated_at not a date', report({ generated_at: 'soon' })],
  ['rows missing', report({ rows: undefined })],
  ['rows not a list', report({ rows: {} })],
  ['a total missing', report({}, { commits: undefined })],
  ['a total not a number', report({}, { running: '2' })],
  ['jobs null', report({}, { jobs: null })],
]
for (const [why, text] of UNREADABLE) {
  test(`R062 AC-5 fleet report unreadable: ${why}`, () => {
    expect(parseFleet(text)).toEqual({ kind: 'error', error: 'fleet report unreadable' })
  })
}

test('R062 AC-4 proposed rules from learn_propose, anything else is an error', () => {
  expect(proposedCount('3 proposed rule(s) for .specclaw/review/rules/learned.md (dry-run…')).toBe(3)
  expect(proposedCount('no recurring lessons (count >= 2) to propose')).toBe(0)
  expect(() => proposedCount('Traceback')).toThrow()
})

const files = (map: Record<string, string>) => async (p: string) => map[p]

test('R062 AC-4 HEAD: a branch ref, packed-refs, detached, a worktree with commondir, no git', async () => {
  expect(await resolveHead(files({ '/r/.git/HEAD': 'ref: refs/heads/main\n', '/r/.git/refs/heads/main': 'aaa\n' }), '/r')).toBe('aaa')
  expect(await resolveHead(files({ '/r/.git/HEAD': 'ref: refs/heads/main\n', '/r/.git/packed-refs': '# pack\nbbb refs/heads/main\n' }), '/r')).toBe('bbb')
  expect(await resolveHead(files({ '/r/.git/HEAD': 'ccc\n' }), '/r')).toBe('ccc')
  expect(await resolveHead(files({
    '/w/.git': 'gitdir: /r/.git/worktrees/w\n', '/r/.git/worktrees/w/HEAD': 'ref: refs/heads/x\n',
    '/r/.git/worktrees/w/commondir': '../..\n', '/r/.git/refs/heads/x': 'ddd\n',
  }), '/w')).toBe('ddd')
  expect(await resolveHead(files({}), '/r')).toBeNull()
})
