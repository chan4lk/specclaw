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
]

for (const [file_path, runs] of ROWS) {
  test(`AC6 the gate ${runs ? 'lets through' : 'holds'} a Write to ${file_path}`, async ($, on) => {
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
