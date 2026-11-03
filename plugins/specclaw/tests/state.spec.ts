import { expect, test } from 'bun:test'
import { parseChange } from '../hooks/core/state.ts'
import { current } from '../hooks/core/view.ts'
import { FULL, LEAN } from './fixtures.ts'

test('AC1 reads full and lean task lists, verdict and PR', () => {
  expect(FULL).toMatchObject({
    phase: 'pr', approved: true, done: 1, total: 3, failed: 1,
    verdict: 'PASS', pr: 'https://x/pr/1',
  })
  expect(LEAN).toMatchObject({ phase: 'build', done: 1, total: 2, failed: 0 })
  expect(parseChange({ name: '004-X', tasks: '- [X] `T1` — a', mtimeMs: 0 }).done).toBe(1)
  expect(parseChange({ name: '002-top', state: '{"phase":"pr","pr":"u"}', mtimeMs: 0 }).pr).toBe('u')
})

test('AC2 malformed or non-object state.json yields phase ? without throwing', () => {
  for (const state of ['{nope', 'null', '42', '[]', '"s"', '', '{"phase":5}']) {
    const change = parseChange({ name: '001-bad', state, mtimeMs: 0 })
    expect(change).toMatchObject({ phase: '?', approved: false, total: 0 })
  }
  const odd = parseChange({ name: '002-odd', state: '{"phases":{"pr":{"url":{}},"verify":{"verdict":1}}}', mtimeMs: 0 })
  expect([odd.pr, odd.verdict]).toEqual([undefined, undefined])
  const typed = parseChange({ name: '003-t', state: '{"phase":7,"phases":{"proposal":{"status":"approved"}}}', mtimeMs: 0 })
  expect(typed.approved).toBe(false)
})

test('AC3 current change is the active one with the newest state.json', () => {
  const archived = { ...FULL, name: '099-old', phase: 'archived', mtimeMs: 99 }
  expect(current([FULL, LEAN, archived])?.name).toBe('047-lean')
})
