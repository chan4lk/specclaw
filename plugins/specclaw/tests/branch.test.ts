import { expect, test } from 'claude-code/testing'

const APPROVED = '{"phase":"build","phases":{"proposal":{"status":"approved"}}}'

const ROWS: [string, string, number, boolean][] = [
  ['on main with an approved change', 'main', 0, false],
  ['on a change branch', 'claude/x', 0, true],
  ['when git fails', 'main', 128, true],
]

for (const [name, branch, exitCode, runs] of ROWS) {
  test(`AC2 a block-mode Write ${runs ? 'runs' : 'is denied'} ${name}`, { options: { gate: 'block' } }, async ($, on) => {
    let ran = false
    on('ui.toast', () => ({ value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: ['/repo', '/repo/src', '/repo/.specclaw', '/repo/.specclaw/changes', '/repo/.specclaw/changes/001-x/state.json'].includes(e.path) }))
    on('fs.list', () => ({ value: [{ name: '001-x', kind: 'dir' }] }))
    on('fs.read', () => ({ value: APPROVED }))
    on('fs.stat', (_, e) => ({ value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }))
    on('process.run', (_, e) => {
      const args = e.argv.slice(3).join(' ')
      const stdout = args === 'branch --show-current' ? branch : args.startsWith('rev-parse') ? 'origin/main' : ''
      return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    const out = await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
    expect(ran).toBe(runs)
    if (!runs) expect(JSON.stringify(out)).toContain('main is the base branch')
  })
}
