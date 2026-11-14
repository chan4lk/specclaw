import { expect, test } from 'claude-code/testing'

const APPROVED = '{"phase":"build","phases":{"proposal":{"status":"approved"}}}'

// Exit codes per git call: [rev-parse --is-inside-work-tree, branch --show-current, symbolic-ref origin/HEAD].
// -1: process.run throws (git missing). Only "not a git repository", a detached HEAD and an unset origin/HEAD
// (symbolic-ref exits 1) pass quietly; every other git failure must fail open with a toast.
const NOT_GIT = 'fatal: not a git repository (or any of the parent directories): .git'
const ROWS: [string, string, number[], string, boolean, boolean][] = [
  ['on main with an approved change', 'main', [0, 0, 0], '', false, false],
  ['on main with no origin/HEAD (symbolic-ref exits 1), falling back to main', 'main', [0, 0, 1], '', false, false],
  ['on a change branch', 'claude/x', [0, 0, 0], '', true, false],
  ['on a detached HEAD', '', [0, 0, 0], '', true, false],
  ['outside git', 'main', [128, 0, 0], NOT_GIT, true, false],
  ['when git refuses a dubious-ownership repo, with a toast', 'main', [128, 0, 0], 'fatal: detected dubious ownership in repository', true, true],
  ['when branch --show-current fails inside a repo, with a toast', 'main', [0, 128, 0], 'fatal: bad object HEAD', true, true],
  ['when symbolic-ref fails hard, with a toast', 'main', [0, 0, 128], 'fatal: bad ref', true, true],
  ['when git cannot run, with a toast', 'main', [-1, 0, 0], '', true, true],
]

for (const [name, branch, codes, stderr, runs, toast] of ROWS) {
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
      // Every git call runs with LC_ALL=C (merged over the host env per ProcessRunInit.env), so the
      // "not a git repository" match below holds in any locale.
      if (e.init?.env?.LC_ALL !== 'C') throw new Error(`git ${e.argv.join(' ')} ran without LC_ALL=C`)
      const call = ['rev-parse', 'branch', 'symbolic-ref'].indexOf(e.argv[3] ?? '')
      const exitCode = codes[call] ?? 0
      if (exitCode === -1) throw new Error('spawn git ENOENT')
      const stdout = exitCode !== 0 ? '' : ['true', branch, 'origin/main'][call] ?? ''
      return { value: { exitCode, stdout, stderr: exitCode === 0 ? '' : stderr, isStdoutTruncated: false, isStderrTruncated: false } }
    })
    on('tool.call', () => ((ran = true), { result: {} }))
    const out = await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
    expect(ran).toBe(runs)
    if (!runs) expect(JSON.stringify(out)).toContain('main is the base branch')
    expect(toasts.some(t => t.includes('branch guard failed'))).toBe(toast)
  })
}

const CONFIGS: [string, string, boolean][] = [
  ['git.base_branch names the base', 'git:\n  strategy: x\n  base_branch: "develop"  # base\n', true],
  ['base_branch outside the git block is ignored', 'jira:\n  base_branch: develop\ngit:\n  strategy: x\n', false],
  ['an empty git.base_branch falls back to origin/HEAD', 'git:\n  base_branch: ""\n', false],
  ['a single-quoted base after a column-0 comment', "git:\n# the trunk\n  base_branch: 'develop'\n", true],
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

test('AC2 a project without .specclaw/ is never branch-guarded, and git is not asked', { options: { gate: 'block' } }, async ($, on) => {
  let ran = false
  let gitCalls = 0
  on('ui.toast', () => ({ value: undefined }))
  on('ui.status', () => ({ value: undefined }))
  on('session.cwd', () => ({ value: '/repo' }))
  on('fs.exists', (_, e) => ({ value: ['/repo', '/repo/src'].includes(e.path) }))
  on('fs.stat', (_, e) => ({ value: { kind: 'dir', size: 0, mtimeMs: 0, isLink: false, realPath: e.path } }))
  on('process.run', () => {
    gitCalls += 1
    return { value: { exitCode: 0, stdout: 'main', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.call', () => ((ran = true), { result: {} }))
  await $.tool.call({ tool: 'Write', file_path: '/repo/src/a.ts', content: 'a' })
  expect([ran, gitCalls]).toEqual([true, 0])
})
