import type { EngineInterface } from 'claude-code'
import { parseChange, type Change, type Snapshot } from './core/state.ts'

const CHANGE_DIR = /^\d{3}-/

async function readText($: EngineInterface, path: string) {
  if (!(await $.fs.exists(path))) return undefined
  const text = await $.fs.read(path)
  if (typeof text !== 'string') throw new Error(`${path} is not text`)
  return text
}

async function readChange($: EngineInterface, root: string, name: string): Promise<Change> {
  const dir = `${root}/${name}`
  const state = await readText($, `${dir}/state.json`)
  const stat = state === undefined ? undefined : await $.fs.stat(`${dir}/state.json`)
  return parseChange({
    name,
    state,
    tasks: await readText($, `${dir}/tasks.md`),
    lean: await readText($, `${dir}/change.md`),
    mtimeMs: stat?.mtimeMs ?? 0,
  })
}

async function readOrUnknown($: EngineInterface, root: string, name: string) {
  return readChange($, root, name).catch(() => parseChange({ name, state: '', mtimeMs: 0 }))
}

export async function readSnapshot($: EngineInterface, cwd: string): Promise<Snapshot> {
  if (!(await $.fs.exists(`${cwd}/.specclaw`))) return { hasSpecclaw: false, changes: [] }
  const root = `${cwd}/.specclaw/changes`
  if (!(await $.fs.exists(root))) return { hasSpecclaw: true, changes: [] }
  const entries = await $.fs.list(root)
  const names = entries.filter(entry => entry.kind === 'dir' && CHANGE_DIR.test(entry.name))
  const changes = await Promise.all(names.map(entry => readOrUnknown($, root, entry.name)))
  return { hasSpecclaw: true, changes }
}
