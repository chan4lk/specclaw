import type { Snapshot } from './state.ts'
import { active } from './view.ts'

export type GateMode = 'block' | 'warn' | 'off'

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
}

const ALLOW: GateVerdict = { action: 'allow' }
const EXEMPT = /^\.(specclaw|git)(\/|$)/
const CHANGE_STATE = /^[^/]+\/state\.json$/i
const STATE_FILE = /^\.specclaw\/changes\/[^/]+\/state\.json$/i

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

export const gateDecision = ({ root, changes, spelled, target, path, mode, snapshot }: GateInput): GateVerdict => {
  if (mode === 'off' || !snapshot.hasSpecclaw) return ALLOW
  if (active(snapshot.changes).some(change => change.approved)) return ALLOW
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
