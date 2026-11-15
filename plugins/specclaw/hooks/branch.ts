import type { EngineInterface } from 'claude-code'
import { baseBranchFrom } from './core/base.ts'

function run($: EngineInterface, cwd: string, args: string[]) {
  // LC_ALL=C keeps git's "not a git repository" in English, whatever the user's locale.
  return $.process.run(['git', '-C', cwd, ...args], { timeoutMs: 3000, env: { LC_ALL: 'C' } })
}

// stdout when git exits with one of `ok` (0 answers stdout, any other ok code ''); any other exit throws.
async function git($: EngineInterface, cwd: string, args: string[], ok = [0]) {
  const ran = await run($, cwd, args)
  if (!ok.includes(ran.exitCode)) throw new Error(`git ${args.join(' ')} exited ${ran.exitCode}: ${ran.stderr.trim()}`)
  return ran.exitCode === 0 ? ran.stdout.trim() : ''
}

// The branch name when the checkout at cwd is on the base branch, resolved in lib/base-ref.sh's order:
// git.base_branch, else origin/HEAD, else main. Only a confirmed "not a git repository" or a detached HEAD
// answers undefined quietly; every other git failure throws, for the caller to toast and fail open.
export async function onBaseBranch($: EngineInterface, cwd: string): Promise<string | undefined> {
  const inside = await run($, cwd, ['rev-parse', '--is-inside-work-tree'])
  if (inside.exitCode !== 0 && /not a git repository/i.test(inside.stderr)) return undefined
  if (inside.exitCode !== 0) throw new Error(`git rev-parse exited ${inside.exitCode}: ${inside.stderr.trim()}`)
  const branch = await git($, cwd, ['branch', '--show-current'])
  if (branch === '') return undefined
  const config = `${cwd}/.specclaw/config.yaml`
  const text = (await $.fs.exists(config)) ? await $.fs.read(config) : ''
  if (typeof text !== 'string') throw new Error(`${config} is not text`)
  const configured = baseBranchFrom(text)
  // symbolic-ref --quiet exits 1 when origin/HEAD is not set: that is "no remote default", not a failure.
  const remote = (await git($, cwd, ['symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD'], [0, 1])).replace(/^origin\//, '')
  const base = configured || remote || 'main'
  return branch === base ? branch : undefined
}
