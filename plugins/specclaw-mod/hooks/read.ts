import type { EngineInterface } from 'claude-code'
import { parseChange, type Change, type Snapshot } from './core/state.ts'

const CHANGE_DIR = /^\d{3}-/

async function readText($: EngineInterface, path: string) {
  if (!(await $.fs.exists(path))) return undefined
  const text = await $.fs.read(path).catch(() => '')
  return typeof text === 'string' ? text : ''
}

async function readChange($: EngineInterface, root: string, name: string): Promise<Change> {
  const dir = `${root}/${name}`
  const stat = await $.fs.stat(`${dir}/state.json`).catch(() => undefined)
  return parseChange({
    name,
    state: await readText($, `${dir}/state.json`),
    tasks: await readText($, `${dir}/tasks.md`),
    lean: await readText($, `${dir}/change.md`),
    mtimeMs: stat?.mtimeMs ?? 0,
  })
}

export async function readSnapshot($: EngineInterface, cwd: string): Promise<Snapshot> {
  if (!(await $.fs.exists(`${cwd}/.specclaw`))) return { hasSpecclaw: false, changes: [] }
  const root = `${cwd}/.specclaw/changes`
  const entries = await $.fs.list(root).catch(() => undefined)
  if (entries === undefined) return { hasSpecclaw: true, isUnreadable: true, changes: [] }
  const names = entries.filter(entry => entry.kind === 'dir' && CHANGE_DIR.test(entry.name))
  const changes = await Promise.all(names.map(entry => readChange($, root, entry.name)))
  return { hasSpecclaw: true, changes }
}
