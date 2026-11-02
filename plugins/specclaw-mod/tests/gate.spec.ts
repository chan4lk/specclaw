import { expect, test } from 'bun:test'
import { gateDecision, type GateMode } from '../hooks/core/gate.ts'
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
