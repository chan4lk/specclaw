import type { Snapshot } from './state.ts'
import { active } from './view.ts'

export type GateMode = 'block' | 'warn' | 'off'

export type GateVerdict =
  | { action: 'allow' }
  | { action: 'deny' | 'warn'; message: string }

export type GateInput = {
  root: string
  target: string | undefined
  path: string
  mode: GateMode
  snapshot: Snapshot
}

const ALLOW: GateVerdict = { action: 'allow' }
const EXEMPT = /^\.(specclaw|git)(\/|$)/i
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

export const gateDecision = ({ root, target, path, mode, snapshot }: GateInput): GateVerdict => {
  if (mode === 'off' || !snapshot.hasSpecclaw) return ALLOW
  if (active(snapshot.changes).some(change => change.approved)) return ALLOW
  if (target === undefined) return held(mode, path)
  const relative = relativeInside(root, target)
  if (relative === undefined) return ALLOW
  if (EXEMPT.test(relative) && !STATE_FILE.test(relative)) return ALLOW
  return held(mode, relative)
}
