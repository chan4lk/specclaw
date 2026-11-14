import { expect, test } from 'claude-code/testing'

const APPROVED = '{"phase":"build","phases":{"proposal":{"status":"approved"}}}'

// exitCode -1: process.run throws (git missing), which must fail open with a toast.
const ROWS: [string, string, number, boolean][] = [
  ['on main with an approved change', 'main', 0, false],
  ['on a change branch', 'claude/x', 0, true],
  ['outside git (git exits 128)', 'main', 128, true],
  ['when git cannot run, with a toast', 'main', -1, true],
]

for (const [name, branch, exitCode, runs] of ROWS) {
  test(`AC2 a block-mode Write ${runs ? 'runs' : 'is denied'} ${name}`, { options: { gate: 'block' } }, async ($, on) => {
    let ran = false
    const toasts: string[] = []
    on('ui.toast', (_, e) => (toasts.push(JSON.stringify(e)), { value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: ['/repo', '/repo/src', '/repo/.specclaw', '/repo/.specclaw/changes', '/repo/.specclaw/changes/001-x/state.json'].includes(e.path) }))
    on('fs.list', () => ({ value: [{ name: '001-x', kind: 'dir' }] }))
    on('fs.read', () => ({ value: APPROVED }))
    on('fs.stat', (_, e) => ({ value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }))
    on('process.run', (_, e) => {
      if (exitCode === -1) throw new Error('spawn git ENOENT')
      const args = e.argv.slice(3).join(' ')
      const stdout = args === 'branch --show-current' ? branch : args.startsWith('symbolic-ref') ? 'origin/main' : ''
      return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    const out = await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
    expect(ran).toBe(runs)
    if (!runs) expect(JSON.stringify(out)).toContain('main is the base branch')
    expect(toasts.some(t => t.includes('branch guard failed'))).toBe(exitCode === -1)
  })
}

const CONFIGS: [string, string, boolean][] = [
  ['git.base_branch names the base', 'git:\n  strategy: x\n  base_branch: "develop"  # base\n', true],
  ['base_branch outside the git block is ignored', 'jira:\n  base_branch: develop\ngit:\n  strategy: x\n', false],
  ['an empty git.base_branch falls back to origin/HEAD', 'git:\n  base_branch: ""\n', false],
]

for (const [name, config, denied] of CONFIGS) {
  test(`AC2 on develop: ${name}`, { options: { gate: 'block' } }, async ($, on) => {
    let ran = false
    on('ui.toast', () => ({ value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/repo' }))
    on('fs.exists', (_, e) => ({ value: ['/repo', '/repo/src', '/repo/.specclaw', '/repo/.specclaw/changes', '/repo/.specclaw/config.yaml', '/repo/.specclaw/changes/001-x/state.json'].includes(e.path) }))
    on('fs.list', () => ({ value: [{ name: '001-x', kind: 'dir' }] }))
    on('fs.read', (_, e) => ({ value: e.path.endsWith('config.yaml') ? config : APPROVED }))
    on('fs.stat', (_, e) => ({ value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }))
    on('process.run', (_, e) => {
      const stdout = e.argv.includes('--show-current') ? 'develop' : 'origin/main'
      return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    await $.tool.call({ tool: 'Write', file_path: '/repo/.specclaw/changes/x/spec.md', content: 'a' })
    ran = false
    await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
    expect(ran).toBe(!denied)
  })
}
