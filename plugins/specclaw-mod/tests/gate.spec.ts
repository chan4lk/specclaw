import { expect, test } from 'bun:test'
import { gateDecision, type GateMode } from '../hooks/core/gate.ts'
import type { Snapshot } from '../hooks/core/state.ts'
import { FULL, NONE, snapshot } from './fixtures.ts'

const UNAPPROVED = snapshot({ ...FULL, approved: false })
const decide = (path: string, state: Snapshot, mode: GateMode) =>
  gateDecision({ cwd: '/repo', path, mode, snapshot: state }).action

const AC6: [string, string, Snapshot, string][] = [
  ['/repo', '/repo/src/a.ts', UNAPPROVED, 'deny'],
  ['/repo', 'README.md', UNAPPROVED, 'deny'],
  ['/repo', '/REPO/src/a.ts', UNAPPROVED, 'deny'],
  ['/repo', '/repo/src/a.ts', snapshot(FULL), 'allow'],
  ['/repo', '/repo/src/a.ts', NONE, 'allow'],
  ['/repo', '/repo/../elsewhere/a.ts', UNAPPROVED, 'allow'],
  ['/repo', '/repo/.git/config', UNAPPROVED, 'allow'],
  ['/repo', '/repo/.specclaw/changes/x/spec.md', UNAPPROVED, 'allow'],
  ['/repo', '/repo/.specclaw/state.json', UNAPPROVED, 'allow'],
  ['/repo', '/repo/.specclaw/changes/x/state.json', UNAPPROVED, 'deny'],
  ['/repo', '/repo/.specclaw/x/../changes/y/state.json', UNAPPROVED, 'deny'],
  ['/repo', '.specclaw\\changes\\x\\state.json', UNAPPROVED, 'deny'],
  ['C:\\proj', 'C:\\proj\\src\\a.ts', UNAPPROVED, 'deny'],
  ['C:\\proj', 'c:\\Proj\\src\\a.ts', UNAPPROVED, 'deny'],
  ['C:\\proj', 'src\\a.ts', UNAPPROVED, 'deny'],
  ['C:\\proj', 'D:\\other\\a.ts', UNAPPROVED, 'allow'],
  ['C:\\proj', '.specclaw\\x.md', UNAPPROVED, 'allow'],
  ['/', '/etc/x', UNAPPROVED, 'deny'],
]

test('AC6 gates project files and state.json only when no approved change is open', () => {
  for (const [cwd, path, state, action] of AC6) {
    expect([path, gateDecision({ cwd, path, mode: 'block', snapshot: state }).action]).toEqual([path, action])
  }
})

test('AC7 warn allows with a message and off allows silently', () => {
  const warned = gateDecision({ cwd: '/repo', path: 'src/a.ts', mode: 'warn', snapshot: UNAPPROVED })
  expect(warned).toEqual({
    action: 'warn',
    message: 'specclaw: no approved change is open. Run /specclaw:propose and get approval before editing src/a.ts.',
  })
  expect(decide('src/a.ts', UNAPPROVED, 'off')).toBe('allow')
  expect(decide('.specclaw/changes/x/state.json', UNAPPROVED, 'warn')).toBe('warn')
})
