import type { EngineInterface } from 'claude-code'

const BASE = /^[ \t]*base_branch:[ \t]*["']?([^"'#\s]*)/m

async function git($: EngineInterface, cwd: string, args: string[]) {
  const ran = await $.process.run(['git', '-C', cwd, ...args], { timeoutMs: 3000 })
  return ran.exitCode === 0 ? ran.stdout.trim() : ''
}

// The branch name when the checkout at cwd is on the base branch (git.base_branch, else origin/HEAD, else main).
// Any failure answers undefined: a broken branch check must never hold an edit.
export async function onBaseBranch($: EngineInterface, cwd: string): Promise<string | undefined> {
  try {
    const branch = await git($, cwd, ['branch', '--show-current'])
    if (branch === '') return undefined
    const config = `${cwd}/.specclaw/config.yaml`
    const text = (await $.fs.exists(config)) ? await $.fs.read(config) : ''
    const configured = typeof text === 'string' ? BASE.exec(text)?.[1] : undefined
    const remote = (await git($, cwd, ['rev-parse', '--abbrev-ref', 'origin/HEAD'])).replace(/^origin\//, '')
    const base = configured || (remote === 'HEAD' ? '' : remote) || 'main'
    return branch === base ? branch : undefined
  } catch {
    return undefined
  }
}
