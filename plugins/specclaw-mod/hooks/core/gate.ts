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
  for (const part of path.split('/')) {
    if (part === '..') parts.pop()
    else if (part !== '' && part !== '.') parts.push(part)
  }
  return '/' + parts.join('/')
}

const relativeInside = (cwd: string, path: string) => {
  const root = normalise(cwd)
  const target = normalise(path.startsWith('/') ? path : `${cwd}/${path}`)
  return target.startsWith(root + '/') ? target.slice(root.length + 1) : undefined
}

export const gateDecision = ({ cwd, path, mode, snapshot }: GateInput): GateVerdict => {
  if (mode === 'off' || !snapshot.hasSpecclaw) return ALLOW
  const relative = relativeInside(cwd, path)
  if (relative === undefined || /^\.(specclaw|git)(\/|$)/.test(relative)) return ALLOW
  if (active(snapshot.changes).some(change => change.approved)) return ALLOW
  return {
    action: mode === 'warn' ? 'warn' : 'deny',
    message: `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing ${relative}.`,
  }
}
