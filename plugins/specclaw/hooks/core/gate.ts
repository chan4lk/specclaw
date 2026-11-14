import type { Snapshot } from './state.ts'
import { active } from './view.ts'

export type GateMode = 'block' | 'warn' | 'off'

const MODES: readonly GateMode[] = ['block', 'warn', 'off']

export function gateMode(raw: unknown): { mode: GateMode; unknown?: string } {
  const value = typeof raw === 'string' ? raw.trim().toLowerCase() : raw
  if (value === undefined || value === '') return { mode: 'warn' }
  return MODES.includes(value as GateMode) ? { mode: value as GateMode } : { mode: 'warn', unknown: String(raw) }
}

export type GateVerdict =
  | { action: 'allow' }
  | { action: 'deny' | 'warn'; message: string }

export type GateInput = {
  root: string
  changes?: string
  spelled?: string
  target: string | undefined
  path: string
  mode: GateMode
  snapshot: Snapshot
  onBase?: string
}

const ALLOW: GateVerdict = { action: 'allow' }
const EXEMPT = /^\.(specclaw|git)(\/|$)/
const TRACKED = String.raw`[^/]+\/(state\.json(\/|$)|(tasks|change)\.md\/)`
const CHANGE_STATE = new RegExp(`^${TRACKED}`, 'i')
const STATE_FILE = new RegExp(String.raw`^\.specclaw(\/changes)?$|^\.specclaw\/changes\/` + TRACKED, 'i')

const slash = (path: string) => path.replaceAll('\\', '/').normalize('NFC')

const relativeInside = (root: string, target: string) => {
  const base = slash(root).replace(/\/+$/, '')
  const prefix = base === '' ? '/' : base + '/'
  const full = slash(target)
  return full.startsWith(prefix) ? full.slice(prefix.length) : undefined
}

const held = (mode: GateMode, file: string): GateVerdict => ({
  action: mode === 'warn' ? 'warn' : 'deny',
  message: `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing ${file}.`,
})

const isStateFile = (changes: string | undefined, target: string) =>
  changes !== undefined && CHANGE_STATE.test(relativeInside(changes, target) ?? '')

const onBaseBranch = (mode: GateMode, branch: string, file: string): GateVerdict => ({
  action: mode === 'warn' ? 'warn' : 'deny',
  message: `specclaw: ${branch} is the base branch. Create a change branch first before editing ${file}.`,
})

export const isGateOpen = (snapshot: Snapshot) =>
  !snapshot.hasSpecclaw || active(snapshot.changes).some(change => change.approved)

export const gateDecision = ({ root, changes, spelled, target, path, mode, snapshot, onBase }: GateInput): GateVerdict => {
  if (mode === 'off') return ALLOW
  const inProject = target === undefined ? undefined : relativeInside(root, target)
  if (onBase !== undefined && snapshot.hasSpecclaw && inProject !== undefined && !EXEMPT.test(inProject)) return onBaseBranch(mode, onBase, inProject)
  if (isGateOpen(snapshot)) return ALLOW
  if (snapshot.isUnreadable || snapshot.changes.some(change => change.isUnreadable)) {
    throw new Error('specclaw: could not read every change')
  }
  if (target === undefined || STATE_FILE.test(spelled ?? '')) return held(mode, path)
  if (isStateFile(changes, target)) return held(mode, path)
  const relative = relativeInside(root, target)
  if (relative === undefined) return ALLOW
  if (EXEMPT.test(relative) && !STATE_FILE.test(relative)) return ALLOW
  return held(mode, relative)
}
