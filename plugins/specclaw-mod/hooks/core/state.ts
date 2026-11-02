export type Change = {
  name: string
  phase: string
  approved: boolean
  done: number
  total: number
  failed: number
  verdict?: string
  pr?: string
  mtimeMs: number
}

export type Snapshot = { hasSpecclaw: boolean; changes: Change[] }

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
    done: marks.filter(mark => mark === 'x').length,
    total: marks.length,
    failed: marks.filter(mark => mark === '!').length,
  }
}

const readJson = (text: string) => {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

export const parseChange = (files: ChangeFiles): Change => {
  const json = files.state === undefined ? {} : readJson(files.state)
  const phases = json?.phases ?? {}
  const tasks = files.tasks ?? leanTasks(files.lean ?? '')
  return {
    name: files.name,
    phase: json === undefined ? '?' : (json.phase ?? 'proposal'),
    approved: phases.proposal?.status === 'approved',
    ...countTasks(tasks),
    verdict: phases.verify?.verdict,
    pr: phases.pr?.url,
    mtimeMs: files.mtimeMs,
  }
}
