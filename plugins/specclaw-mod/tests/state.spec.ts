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
})

test('AC2 malformed state.json yields phase ? without throwing', () => {
  const change = parseChange({ name: '001-bad', state: '{nope', mtimeMs: 0 })
  expect(change).toMatchObject({ phase: '?', approved: false, total: 0 })
})

test('AC3 current change is the active one with the newest state.json', () => {
  const archived = { ...FULL, name: '099-old', phase: 'archived', mtimeMs: 99 }
  expect(current([FULL, LEAN, archived])?.name).toBe('047-lean')
})
