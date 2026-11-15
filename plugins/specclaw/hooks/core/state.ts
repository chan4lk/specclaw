import type { SpecclawChange, SpecclawSnapshot } from '../../types/index.d.ts'

export type Change = SpecclawChange
export type Snapshot = SpecclawSnapshot

export type ChangeFiles = {
  name: string
  state?: string
  tasks?: string
  lean?: string
  mtimeMs: number
}

const TASK_LINE = /^\s*- \[(.)\] `T\d+`/gm

const leanTasks = (text: string) => {
  const start = text.search(/^## Tasks\s*$/m)
  if (start < 0) return ''
  const rest = text.slice(start + 1)
  const end = rest.search(/^## /m)
  return end < 0 ? rest : rest.slice(0, end)
}

export const countTasks = (text: string) => {
  const marks = [...text.matchAll(TASK_LINE)].map(match => match[1])
  return {
    done: marks.filter(mark => mark?.toLowerCase() === 'x').length,
    total: marks.length,
    failed: marks.filter(mark => mark === '!').length,
  }
}

const readJson = (text: string) => {
  try {
    const value = JSON.parse(text)
    return typeof value === 'object' && value !== null && !Array.isArray(value) ? value : undefined
  } catch {
    return undefined
  }
}

const text = (value: unknown) => (typeof value === 'string' ? value : undefined)

const phaseOf = (json: Record<string, unknown> | undefined) => {
  if (json === undefined) return '?'
  return json.phase === undefined ? 'proposal' : (text(json.phase) ?? '?')
}

export const parseChange = (files: ChangeFiles): Change => {
  const json = files.state === undefined ? {} : readJson(files.state)
  const phases = json?.phases ?? {}
  const tasks = files.tasks ?? leanTasks(files.lean ?? '')
  const phase = phaseOf(json)
  return {
    name: files.name,
    phase,
    approved: phase !== '?' && phases.proposal?.status === 'approved',
    ...countTasks(tasks),
    verdict: text(phases.verify?.verdict),
    pr: text(phases.pr?.url) ?? text(json?.pr),
    mtimeMs: files.mtimeMs,
  }
}
