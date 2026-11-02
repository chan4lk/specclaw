import type { Snapshot } from './state.ts'
import { active } from './view.ts'

export type GateMode = 'block' | 'warn' | 'off'

export type GateVerdict =
  | { action: 'allow' }
  | { action: 'deny' | 'warn'; message: string }

export type GateInput = {
  cwd: string
  path: string
  mode: GateMode
  snapshot: Snapshot
}

const ALLOW: GateVerdict = { action: 'allow' }

const normalise = (path: string) => {
  const parts: string[] = []
  for (const part of path.replaceAll('\\', '/').split('/')) {
    if (part === '..') parts.pop()
    else if (part !== '' && part !== '.') parts.push(part)
  }
  return '/' + parts.join('/')
}

const relativeInside = (cwd: string, path: string) => {
  const root = normalise(cwd)
  const isAbsolute = /^([A-Za-z]:)?[\\/]/.test(path)
  const target = normalise(isAbsolute ? path : `${cwd}/${path}`)
  const prefix = root === '/' ? '/' : root + '/'
  const isInside = target.toLowerCase().startsWith(prefix.toLowerCase())
  return isInside ? target.slice(prefix.length) : undefined
}

const EXEMPT = /^\.(specclaw|git)(\/|$)/i
const STATE_FILE = /^\.specclaw\/changes\/[^/]+\/state\.json$/i

export const gateDecision = ({ cwd, path, mode, snapshot }: GateInput): GateVerdict => {
  if (mode === 'off' || !snapshot.hasSpecclaw) return ALLOW
  const relative = relativeInside(cwd, path)
  if (relative === undefined) return ALLOW
  if (EXEMPT.test(relative) && !STATE_FILE.test(relative)) return ALLOW
  if (active(snapshot.changes).some(change => change.approved)) return ALLOW
  return {
    action: mode === 'warn' ? 'warn' : 'deny',
    message: `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing ${relative}.`,
  }
}
