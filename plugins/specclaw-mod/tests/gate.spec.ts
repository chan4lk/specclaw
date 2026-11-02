import { expect, test } from 'bun:test'
import { gateDecision, type GateMode } from '../hooks/core/gate.ts'
import type { Snapshot } from '../hooks/core/state.ts'
import { FULL, NONE, snapshot } from './fixtures.ts'

const UNAPPROVED = snapshot({ ...FULL, approved: false })
const decide = (path: string, state: Snapshot, mode: GateMode = 'block') =>
  gateDecision({ cwd: '/repo', path, mode, snapshot: state }).action

test('AC6 denies source edits only when no approved change is open', () => {
  expect(decide('/repo/src/a.ts', UNAPPROVED)).toBe('deny')
  expect(decide('README.md', UNAPPROVED)).toBe('deny')
  expect(decide('/repo/src/a.ts', snapshot(FULL))).toBe('allow')
  expect(decide('/repo/.specclaw/changes/x/spec.md', UNAPPROVED)).toBe('allow')
  expect(decide('/repo/.git/config', UNAPPROVED)).toBe('allow')
  expect(decide('/repo/../elsewhere/a.ts', UNAPPROVED)).toBe('allow')
  expect(decide('/repo/src/a.ts', NONE)).toBe('allow')
  expect(decide('/repo/.specclaw/changes/x/state.json', UNAPPROVED)).toBe('deny')
  for (const [cwd, path] of [['C:\\proj', 'C:\\proj\\src\\a.ts'], ['C:\\proj', 'src\\a.ts'], ['/', '/etc/x']]) {
    expect(gateDecision({ cwd, path, mode: 'block', snapshot: UNAPPROVED }).action).toBe('deny')
  }
})

test('AC7 warn allows with a message and off allows silently', () => {
  const warned = gateDecision({ cwd: '/repo', path: 'src/a.ts', mode: 'warn', snapshot: UNAPPROVED })
  expect(warned).toEqual({
    action: 'warn',
    message: 'specclaw: no approved change is open. Run /specclaw:propose and get approval before editing src/a.ts.',
  })
  expect(decide('src/a.ts', UNAPPROVED, 'off')).toBe('allow')
})
