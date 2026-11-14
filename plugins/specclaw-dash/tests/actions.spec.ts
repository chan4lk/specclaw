import { expect, test } from 'bun:test'
import type { ChangeRow } from '../types/index.d.ts'
import { commands, dryRunResult, launchItems, parseCaps, parseDismissed, unwrap, wrap } from '../hooks/core/actions.ts'

const DIR = "/r/it's/.specclaw"

test('R063 AC-1 each action is exactly its existing command', () => {
  expect(commands.dryRun(['063-a', 'devloop'])).toBe('specclaw-fleet optin 063-a devloop --dry-run')
  expect(commands.launch(['063-a', '064-b', 'devloop'])).toBe(
    'specclaw-fleet optin 063-a 064-b devloop && specclaw-fleet trigger 063-a && specclaw-fleet trigger 064-b && specclaw-fleet feature start devloop')
  expect(commands.approve('0a1b2c3d4e5f')).toBe('specclaw-review learn --apply 0a1b2c3d4e5f')
  expect(commands.reject('0a1b2c3d4e5f')).toBe('specclaw-review learn --reject 0a1b2c3d4e5f')
  expect(commands.caps(DIR)).toBe(`specclaw-budget roles --json '/r/it'\\''s/.specclaw'`)
  expect(commands.setCap(DIR, 'coding', ' 120000 ')).toBe(`specclaw-budget set '/r/it'\\''s/.specclaw' coding 120000`)
  expect(commands.dismissed(DIR)).toBe(`specclaw-suggest '/r/it'\\''s/.specclaw' --dismissed`)
  expect(commands.undismiss(DIR, 'fleet')).toBe(`specclaw-suggest '/r/it'\\''s/.specclaw' --undismiss fleet`)
})

test('R063 AC-2 a value that fails its pattern is refused before any command exists', () => {
  expect(() => commands.dryRun([])).toThrow(/select at least one/)
  expect(() => commands.launch(['063-a; rm -rf ~'])).toThrow(/refused: feature module/)
  expect(() => commands.dryRun(['$(id)'])).toThrow(/refused/)
  expect(() => commands.approve('abc def')).toThrow(/refused: fingerprint/)
  expect(() => commands.setCap(DIR, 'coding', '12e3')).toThrow(/refused: number/)
  expect(() => commands.setCap(DIR, 'Coding;', '1')).toThrow(/refused: role/)
  expect(() => commands.undismiss(DIR, 'fleet`x`')).toThrow(/refused: feature/)
})

const row = (name: string, o: Partial<ChangeRow>): ChangeRow =>
  ({ name, phase: 'tasks', done: 0, total: 0, failed: 0, verdict: null, pr: null, span: null, approved: true, feature: null, ...o })

test('R063 AC-1 Launch offers approved changes before build with no PR, then feature modules', () => {
  expect(launchItems([
    row('060-a', {}), row('061-b', { approved: false }), row('062-c', { phase: 'build' }), row('063-d', { pr: 'u' }),
    row('064-e', { feature: 'devloop' }), row('065-f', { phase: 'verify', feature: 'devloop' }), row('066-g', { feature: 'cat' }),
  ])).toEqual(['060-a', '064-e', '066-g', 'cat', 'devloop'])
})

test('R063 AC-3 only items the dry run will assign to and tag as the user are launchable', () => {
  const out = [
    '063-a: would assign to me@x.com and add fleet:auto as me@x.com',
    '064-b: refused: assigned to other@x.com; only they can opt in',
    'devloop: already opted in by me@x.com',
    '065-c: could not read the work item',
  ].join('\n')
  expect(dryRunResult(['063-a', '064-b', 'devloop', '065-c', '066-d'], out)).toEqual({ launchable: ['063-a', 'devloop'], named: 4 })
  expect(dryRunResult(['063-a'], 'specclaw-fleet: could not read the identity behind AZDO_TOKEN')).toEqual({ launchable: [], named: 0 })
})

test('R063 AC-1 caps JSON from specclaw-budget roles (065), sorted; any other shape is an error', () => {
  const json = '{"review":{"context":60000,"default":80000,"min":20000,"max":200000,"source":"config"},"coding":{"context":120000,"default":120000,"min":40000,"max":400000,"source":"default"}}'
  expect(parseCaps(json).map(c => [c.role, c.context, c.source])).toEqual([['coding', 120000, 'default'], ['review', 60000, 'config']])
  expect(() => parseCaps('[]')).toThrow()
  expect(() => parseCaps('{"x":{"context":"1","default":1,"min":1,"max":2,"source":"default"}}')).toThrow(/role x/)
  expect(() => parseCaps('not json')).toThrow()
})

test('R063 AC-1 the dismissed list, and the exit code the runner appends', () => {
  expect(parseDismissed('review\nbf\n\n')).toEqual(['review', 'bf'])
  expect(wrap('/r', 'specclaw-x')).toBe(`{ cd '/r' && { specclaw-x ; } ; } 2>&1; echo "__dash_exit=$?"`)
  expect(unwrap('line\n__dash_exit=4\n')).toEqual({ code: 4, out: 'line' })
  expect(unwrap('cut off')).toEqual({ code: -1, out: 'cut off' })
})
