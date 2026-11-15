import { expect, test } from 'claude-code/testing'

const REAL: Record<string, string> = {
  '/repo': '/repo',
  '/repo/src': '/repo/src',
  '/repo/src/a.ts': '/repo/src/a.ts',
  '/link': '/repo',
  '/elsewhere': '/elsewhere',
  '/repo/.specclaw': '/repo/.specclaw',
  '/repo/.specclaw/changes': '/repo/.specclaw/changes',
  '/repo/.specclaw/changes/x': '/repo/.specclaw/changes/x',
  '/REPO': '/repo',
  '/repo/SRC': '/repo/src',
  '/REPO/.specclaw/changes/x': '/repo/.specclaw/changes/x',
  '/repo/linked': '/outside',
  '/outside': '/outside',
  '/outside/changes': '/outside/changes',
  '/outside/changes/y': '/outside/changes/y',
}

const ROWS: [string, boolean][] = [
  ['/repo/src/a.ts', false],
  ['src/new.ts', false],
  ['/link/src/a.ts', false],
  ['/repo/new/dir/a.ts', false],
  ['/elsewhere/a.ts', true],
  ['/link/../elsewhere/a.ts', true],
  ['/repo/.specclaw/changes/x/spec.md', true],
  ['\\\\?\\C:\\repo\\a.ts', false],
  ['//server/share/a.ts', false],
  ['C:a.ts', false],
  ['/repo/.specclaw/changes/x/state.json::$DATA', false],
  ['/repo/.specclaw/changes/x/state.json.', false],
  ['/repo/missing/../a.ts', false],
  ['/repo/.specclaw/changes/new/state.json', false],
  ['/repo/.specclaw/changes/x/State.json', false],
  ['/repo/.specclaw/changes/x/STATE.JSON', false],
  ['/repo/linked/changes/y/spec.md', true],
  ['/repo/.specclaw/changes/x/state.json/foo', false],
  ['/repo/.specclaw/changes/x/Tasks.md/foo', false],
  ['/repo/.specclaw/changes/x/change.md/foo', false],
  ['/repo/.specclaw/changes/x/change.md', true],
  ['/repo/.specclaw/changes/x/tasks.md', true],
  ['/repo/.specclaw/changes', false],
  ['/REPO/src/a.ts', false],
  ['/repo/SRC/new.ts', false],
  ['/REPO/.specclaw/changes/x/state.json', false],
  ['/repo/.SpecClaw', false],
]

for (const [file_path, runs] of ROWS) {
  test(`AC6 the gate ${runs ? 'lets through' : 'holds'} a Write to ${file_path}`, { options: { gate: 'block' } }, async ($, on) => {
    let ran = false
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: REAL[e.path] !== undefined }))
    on('fs.list', () => ({ value: [] }))
    on('fs.stat', (_, e) => {
      const realPath = REAL[e.path === '/link/..' ? '/' : e.path] ?? (e.path === '/' ? '/' : undefined)
      if (realPath === undefined) return { deny: 'ENOENT' }
      return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath } }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    await $.tool.call({ tool: 'Write', file_path, content: 'a' })
    expect([file_path, ran]).toEqual([file_path, runs])
  })
}

test('AC6 with no gate option set, the default is warn: the Write runs and a toast names the gate', async ($, on) => {
  let ran = false
  const toasts: string[] = []
  on('ui.toast', (_, e) => (toasts.push(JSON.stringify(e)), { value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/repo' }))
  on('fs.exists', (_, e) => ({ value: REAL[e.path] !== undefined }))
  on('fs.list', () => ({ value: [] }))
  on('fs.stat', (_, e) => (REAL[e.path] ? { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: REAL[e.path] } } : { deny: 'ENOENT' }))
  on('tool.call', () => ((ran = true), { result: {} }))
  await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
  expect([ran, toasts.some(t => t.includes('/specclaw:propose'))]).toEqual([true, true])
})
