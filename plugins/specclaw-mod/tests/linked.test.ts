import { expect, test } from 'claude-code/testing'

const LAYOUTS: [string, Record<string, string>][] = [
  ['.specclaw linked out', { '/repo': '/repo', '/repo/.specclaw': '/out/sc', '/repo/.specclaw/changes': '/out/sc/changes', '/repo/.specclaw/changes/x': '/out/sc/changes/x' }],
  ['changes linked out', { '/repo': '/repo', '/repo/.specclaw': '/repo/.specclaw', '/repo/.specclaw/changes': '/out/ch', '/repo/.specclaw/changes/x': '/out/ch/x' }],
  ['one change linked out', { '/repo': '/repo', '/repo/.specclaw': '/repo/.specclaw', '/repo/.specclaw/changes': '/repo/.specclaw/changes', '/repo/.specclaw/changes/x': '/out/x' }],
]

const ROWS: [string, boolean][] = [
  ['.specclaw/changes/x/state.json', false],
  ['.specclaw/changes/x/State.json', false],
  ['.specclaw/changes/new/state.json', false],
  ['.specclaw/changes/x/spec.md', true],
]

for (const [layout, real] of LAYOUTS) {
  for (const [file_path, runs] of ROWS) {
    test(`AC6 with ${layout}, a Write to ${file_path} ${runs ? 'runs' : 'is held'}`, async ($, on) => {
      let ran = false
      on('session.cwd', () => ({ value: '/repo' }))
      on('fs.exists', (_, e) => ({ value: real[e.path] !== undefined }))
      on('fs.list', () => ({ value: [] }))
      on('fs.stat', (_, e) => {
        const realPath = real[e.path] ?? (e.path === '/' ? '/' : undefined)
        if (realPath === undefined) return { deny: 'ENOENT' }
        return { value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath } }
      })
      on('tool.call', () => ((ran = true), { result: {} }))
      await $.tool.call({ tool: 'Write', file_path, content: 'a' })
      expect([layout, file_path, ran]).toEqual([layout, file_path, runs])
    })
  }
}
