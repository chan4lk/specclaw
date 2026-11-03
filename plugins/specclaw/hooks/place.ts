import type { EngineInterface } from 'claude-code'

const UNPLACEABLE = /^(?:[A-Za-z]:(?![\\/])|\\\\|\/\/)/
const ABSOLUTE = /^(?:[A-Za-z]:)?[\\/]/
const BAD_NAME = /^$|^\.\.?$|:|[. ]$/

const MISSING = /\b(ENOENT|ENOTDIR)\b/

async function realPathOf($: EngineInterface, path: string) {
  try {
    return (await $.fs.stat(path, { resolve: true })).realPath
  } catch (error) {
    if (MISSING.test(error instanceof Error ? error.message : String(error))) return undefined
    throw error
  }
}

const parentOf = (dir: string) => {
  const cut = Math.max(dir.lastIndexOf('/'), dir.lastIndexOf('\\'))
  if (cut < 0) return undefined
  const parent = dir.slice(0, cut)
  return parent === '' || /^[A-Za-z]:$/.test(parent) ? dir.slice(0, cut + 1) : parent
}

async function placePath($: EngineInterface, cwd: string, path: string) {
  if (UNPLACEABLE.test(path)) return undefined
  let dir = ABSOLUTE.test(path) ? path : `${cwd}/${path}`
  const names: string[] = []
  for (let depth = 0; depth < 256; depth += 1) {
    const real = await realPathOf($, dir)
    if (real !== undefined) return [real.replace(/[\\/]+$/, ''), ...names].join('/')
    const parent = parentOf(dir)
    const name = dir.slice((parent ?? '').length).replace(/^[\\/]/, '')
    if (parent === undefined || parent === dir || BAD_NAME.test(name)) return undefined
    names.unshift(name)
    dir = parent
  }
  return undefined
}

const spelledInCwd = (cwd: string, path: string) => {
  const parts: string[] = []
  const full = ABSOLUTE.test(path) ? path : `${cwd}/${path}`
  for (const part of full.replaceAll('\\', '/').split('/')) {
    if (part === '..') parts.pop()
    else if (part !== '' && part !== '.') parts.push(part)
  }
  const base = cwd.replaceAll('\\', '/').split('/').filter(part => part !== '' && part !== '.')
  const isInside = base.every((part, index) => parts[index]?.toLowerCase() === part.toLowerCase())
  return isInside ? parts.slice(base.length).join('/') : undefined
}

export async function placeInCwd($: EngineInterface, path: string) {
  const cwd = await $.session.cwd()
  const root = await realPathOf($, cwd)
  if (root === undefined) throw new Error(`specclaw: cannot resolve ${cwd}`)
  const changes = await placePath($, cwd, '.specclaw/changes')
  return { root, changes, spelled: spelledInCwd(cwd, path), target: await placePath($, cwd, path) }
}
