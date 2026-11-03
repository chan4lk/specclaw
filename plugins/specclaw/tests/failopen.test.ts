import { expect, test } from 'claude-code/testing'

const APPROVED = '{"phase":"build","phases":{"proposal":{"status":"approved"}}}'
const STATE = '/repo/.specclaw/changes/001-a/state.json'
const DIRS = new Set(['/repo', '/repo/src', '/repo/.specclaw', '/repo/.specclaw/changes'])

const ROWS: [string, string, { read?: unknown; stat?: unknown }][] = [
  ['fs.read rejects on an approved state.json', '/repo/src/a.ts', { read: { deny: 'EIO' } }],
  ['fs.read answers a non-string', '/repo/src/a.ts', { read: { value: { base64: 'AA==' } } }],
  ['fs.stat rejects on an approved state.json', '/repo/src/a.ts', { stat: { deny: 'EACCES' } }],
  ['fs.stat refuses a link into the project', '/link/src/a.ts', { stat: { deny: 'EACCES' } }],
  ['fs.stat refuses a new file under a link', '/link/new/a.ts', { stat: { deny: 'EACCES' } }],
]

for (const [why, file_path, fault] of ROWS) {
  test(`FR8 a gate read failure lets the Write run with a toast: ${why}`, async ($, on) => {
    let ran = false
    const toasts: unknown[] = []
    on('ui.toast', (_, e) => (toasts.push(e), { value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: DIRS.has(e.path) || e.path === STATE }))
    on('fs.list', () => ({ value: [{ name: '001-a', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] }))
    on('fs.read', (_, e) => (e.path === STATE && fault.read ? fault.read : { value: e.path === STATE ? APPROVED : '' }))
    on('fs.stat', (_, e) => {
      const faulty = e.path === STATE || e.path.startsWith('/link')
      if (faulty && fault.stat) return fault.stat
      if (DIRS.has(e.path) || e.path === STATE) return { value: { kind: 'dir', size: 0, mtimeMs: 1, isLink: false, realPath: e.path } }
      return { deny: 'ENOENT' }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    await $.tool.call({ tool: 'Write', file_path, content: 'a' })
    expect([ran, toasts.length > 0]).toEqual([true, true])
  })
}
