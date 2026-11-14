import type { EngineInterface } from 'claude-code'

// git.base_branch, read only inside the top-level `git:` block, as lib/base-ref.sh reads it.
const GIT_BLOCK = /^git:[^\n]*\n((?:[ \t]+[^\n]*\n?|\n)*)/m
const BASE = /^  base_branch:[ \t]*["']?([^"'#\s]*)/m

async function git($: EngineInterface, cwd: string, args: string[]) {
  const ran = await $.process.run(['git', '-C', cwd, ...args], { timeoutMs: 3000 })
  return ran.exitCode === 0 ? ran.stdout.trim() : ''
}

// The branch name when the checkout at cwd is on the base branch, resolved in lib/base-ref.sh's order:
// git.base_branch, else origin/HEAD, else main. Outside git or on a detached HEAD it answers undefined.
// A throw (git missing, an unreadable config) is the caller's to surface: the guard then fails open.
export async function onBaseBranch($: EngineInterface, cwd: string): Promise<string | undefined> {
  const branch = await git($, cwd, ['branch', '--show-current'])
  if (branch === '') return undefined
  const config = `${cwd}/.specclaw/config.yaml`
  const text = (await $.fs.exists(config)) ? await $.fs.read(config) : ''
  if (typeof text !== 'string') throw new Error(`${config} is not text`)
  const configured = BASE.exec(GIT_BLOCK.exec(text)?.[1] ?? '')?.[1]
  const remote = (await git($, cwd, ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD'])).replace(/^origin\//, '')
  const base = configured || remote || 'main'
  return branch === base ? branch : undefined
}
