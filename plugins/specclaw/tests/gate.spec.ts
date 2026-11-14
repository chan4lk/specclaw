import { expect, test } from 'bun:test'
import { gateDecision, gateMode, type GateMode } from '../hooks/core/gate.ts'
import type { Snapshot } from '../hooks/core/state.ts'
import { FULL, NONE, snapshot } from './fixtures.ts'

const UNAPPROVED = snapshot({ ...FULL, approved: false })
const decide = (target: string | undefined, state: Snapshot, mode: GateMode = 'block') =>
  gateDecision({ root: '/repo', target, path: target ?? 'odd', mode, snapshot: state }).action

const AC6: [string | undefined, Snapshot, string][] = [
  ['/repo/src/a.ts', UNAPPROVED, 'deny'],
  ['/repo/README.md', UNAPPROVED, 'deny'],
  [undefined, UNAPPROVED, 'deny'],
  ['/repo/src/a.ts', snapshot(FULL), 'allow'],
  [undefined, snapshot(FULL), 'allow'],
  ['/repo/src/a.ts', NONE, 'allow'],
  ['/elsewhere/a.ts', UNAPPROVED, 'allow'],
  ['/repository/a.ts', UNAPPROVED, 'allow'],
  ['/repo/.git/config', UNAPPROVED, 'allow'],
  ['/repo/.GIT/config', UNAPPROVED, 'deny'],
  ['/repo/.specclaw/changes/x/spec.md', UNAPPROVED, 'allow'],
  ['/repo/.specclaw/state.json', UNAPPROVED, 'allow'],
  ['/repo/.specclaw/changes/x/sub/state.json', UNAPPROVED, 'allow'],
  ['/repo/.specclaw/changes/x/state.json', UNAPPROVED, 'deny'],
  ['/repo/.specclaw/changes/x/STATE.JSON', UNAPPROVED, 'deny'],
  ['\\repo\\.specclaw\\changes\\x\\state.json', UNAPPROVED, 'deny'],
  ['/repo/cafe\u0301.ts', UNAPPROVED, 'deny'],
]

test('AC6 gates resolved project files, state.json and unplaceable paths only when no change is approved', () => {
  for (const [target, state, action] of AC6) {
    expect([target, decide(target, state)]).toEqual([target, action])
  }
  const windows = gateDecision({ root: 'C:\\proj', target: 'C:\\proj\\src\\a.ts', path: 'a', mode: 'block', snapshot: UNAPPROVED })
  const atRoot = gateDecision({ root: '/', target: '/etc/x', path: 'a', mode: 'block', snapshot: UNAPPROVED })
  expect([windows.action, atRoot.action]).toEqual(['deny', 'deny'])
  const linked = (target: string) =>
    gateDecision({ root: '/repo', changes: '/outside/changes', target, path: 'p', mode: 'block', snapshot: UNAPPROVED }).action
  expect([linked('/outside/changes/x/state.json'), linked('/outside/changes/x/STATE.json'), linked('/outside/changes/x/spec.md')]).toEqual(['deny', 'deny', 'allow'])
  const unreadable = snapshot({ ...FULL, approved: false, isUnreadable: true })
  expect(() => decide('/repo/src/a.ts', unreadable)).toThrow('could not read every change')
  expect(() => decide('/repo/src/a.ts', { ...UNAPPROVED, isUnreadable: true })).toThrow()
  expect(decide('/repo/src/a.ts', snapshot(FULL, { ...FULL, isUnreadable: true }))).toBe('allow')
})

test('AC7 warn allows with a message and off allows silently', () => {
  const warned = gateDecision({ root: '/repo', target: '/repo/src/a.ts', path: 'src/a.ts', mode: 'warn', snapshot: UNAPPROVED })
  expect(warned).toEqual({
    action: 'warn',
    message: 'specclaw: no approved change is open. Run /specclaw:propose and get approval before editing src/a.ts.',
  })
  expect(decide('/repo/src/a.ts', UNAPPROVED, 'off')).toBe('allow')
  expect(decide(undefined, UNAPPROVED, 'warn')).toBe('warn')
})

const MODE_ROWS: [unknown, ReturnType<typeof gateMode>][] = [
  [undefined, { mode: 'warn' }],
  ['', { mode: 'warn' }],
  ['block', { mode: 'block' }],
  [' Block ', { mode: 'block' }],
  ['OFF', { mode: 'off' }],
  ['deny', { mode: 'warn', unknown: 'deny' }],
  [true, { mode: 'warn', unknown: 'true' }],
  [null, { mode: 'warn', unknown: 'null' }],
  [3, { mode: 'warn', unknown: '3' }],
]
for (const [raw, want] of MODE_ROWS) {
  test(`AC7 gate setting ${JSON.stringify(raw)} reads as ${want.mode}${want.unknown ? ' and is reported' : ''}`, () => {
    expect(gateMode(raw)).toEqual(want)
  })
}

test('AC1 the base branch holds project edits, even with an approved change, and leaves .specclaw/, .git/ and non-specclaw projects alone', () => {
  const onMain = (target: string, mode: GateMode = 'block', state: Snapshot = snapshot(FULL)) =>
    gateDecision({ root: '/repo', target, path: target, mode, snapshot: state, onBase: 'main' })
  expect(onMain('/repo/src/a.ts')).toEqual({
    action: 'deny',
    message: 'specclaw: main is the base branch. Create a change branch first before editing src/a.ts.',
  })
  expect(onMain('/repo/src/a.ts', 'warn').action).toBe('warn')
  expect(onMain('/repo/src/a.ts', 'off').action).toBe('allow')
  expect(onMain('/repo/src/a.ts', 'block', NONE).action).toBe('allow')
  expect([onMain('/repo/.specclaw/changes/x/spec.md'), onMain('/repo/.git/config'), onMain('/elsewhere/a.ts')].map(v => v.action))
    .toEqual(['allow', 'allow', 'allow'])
  expect(gateDecision({ root: '/repo', target: '/repo/src/a.ts', path: 'a', mode: 'block', snapshot: snapshot(FULL) }).action).toBe('allow')
})
