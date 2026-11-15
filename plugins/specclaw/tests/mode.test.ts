import { expect, test } from 'claude-code/testing'

const MODES: [string, boolean, boolean][] = [
  ['deny', true, true],
  [' Block ', false, false],
  ['warn', true, false],
]

for (const [gate, runs, named] of MODES) {
  test(`AC7 gate "${gate}" ${runs ? 'lets' : 'stops'} an unapproved Write${named ? ' and names the bad value' : ''}`, { options: { gate } }, async ($, on) => {
    let ran = false
    const toasts: string[] = []
    on('ui.toast', (_, e) => (toasts.push(JSON.stringify(e)), { value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: ['/repo', '/repo/src', '/repo/.specclaw', '/repo/.specclaw/changes'].includes(e.path) }))
    on('fs.list', () => ({ value: [] }))
    on('fs.stat', (_, e) => ({ value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }))
    on('session.start', (_, e) => ({ cwd: e.cwd }))
    on('command.register', () => ({ value: { command: 'specclaw-pane' } }))
    on('tool.call', () => ((ran = true), { result: {} }))
    await $.session.start({ cwd: '/repo', surface: 'terminal', isInteractive: true })
    await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
    expect([ran, toasts.some(t => t.includes(`unknown gate mode \\"${gate}\\"`))]).toEqual([runs, named])
  })
}
