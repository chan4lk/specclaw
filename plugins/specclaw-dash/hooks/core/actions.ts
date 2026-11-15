// Each pane action as the one existing command it runs, and parsers for what those print. Pure; the commands decide.
import type { CapRow, ChangeRow, Section } from '../../types/index.d.ts'

// Every value put into a command must match its pattern, or the action is refused before a command exists.
const CHANGE = /^\d{3}-[a-z0-9][a-z0-9-]*$/
const PATTERNS = { 'feature module': /^[a-z][a-z0-9_-]*$/, fingerprint: /^[0-9a-f]{6,64}$/, role: /^[a-z][a-z0-9_-]*$/,
  number: /^\d{1,9}$/, feature: /^[a-z]+$/ } as const

export const valid = (what: keyof typeof PATTERNS, value: string) => {
  if (!PATTERNS[what].test(value)) throw new Error(`refused: ${what} ${JSON.stringify(value)} is not a valid value`)
  return value
}
const item = (v: string) => (CHANGE.test(v) ? v : valid('feature module', v))
const items = (list: string[]) => {
  if (list.length === 0) throw new Error('refused: select at least one change or feature')
  return list.map(item).join(' ')
}
export const quote = (s: string) => `'${s.replaceAll("'", `'\\''`)}'`

export const commands = {
  dryRun: (list: string[]) => `specclaw-fleet optin ${items(list)} --dry-run`,
  // optin first: it assigns each item to the user and adds fleet:auto as the user, and refuses an item that is
  // someone else's; trigger and feature start then check that consent again before they spend a plan.
  launch: (list: string[]) => [`specclaw-fleet optin ${items(list)}`,
    ...list.map(i => (CHANGE.test(i) ? `specclaw-fleet trigger ${i}` : `specclaw-fleet feature start ${i}`))].join(' && '),
  approve: (fp: string) => `specclaw-review learn --apply ${valid('fingerprint', fp)}`,
  reject: (fp: string) => `specclaw-review learn --reject ${valid('fingerprint', fp)}`,
  caps: (dir: string) => `specclaw-budget roles --json ${quote(dir)}`,
  setCap: (dir: string, role: string, n: string) => `specclaw-budget set ${quote(dir)} ${valid('role', role)} ${valid('number', n.trim())}`,
  dismissed: (dir: string) => `specclaw-suggest ${quote(dir)} --dismissed`,
  undismiss: (dir: string, feature: string) => `specclaw-suggest ${quote(dir)} --undismiss ${valid('feature', feature)}`,
}

// What Launch offers: approved changes not yet built and with no PR, then the `**Feature:**` modules.
const BEFORE_BUILD = new Set(['proposal', 'spec', 'design', 'tasks'])
export const launchItems = (changes: ChangeRow[]) => [
  ...changes.filter(c => c.approved && BEFORE_BUILD.has(c.phase) && c.pr === null).map(c => c.name),
  ...[...new Set(changes.flatMap(c => (c.feature ? [c.feature] : [])))].sort(),
]

// `optin --dry-run` prints `<item>: …` per item; only `would …` and `already opted in by …` can launch (never
// `refused: assigned to …`, someone else's). No line for any item: fleet could not run at all (not set up).
export const dryRunResult = (list: string[], out: string) => {
  const said = (i: string) => out.split('\n').find(l => l.startsWith(`${i}: `))?.slice(i.length + 2)
  return {
    launchable: list.filter(i => /^(would |already opted in by )/.test(said(i) ?? '')),
    named: list.filter(i => said(i) !== undefined).length,
  }
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const int = (v: unknown) => typeof v === 'number' && Number.isInteger(v)

// `specclaw-budget roles --json` (065): {"<role>": {"context", "default", "min", "max", "source"}, ...}.
export const parseCaps = (text: string): CapRow[] => {
  const doc: unknown = JSON.parse(text)
  if (!isObject(doc)) throw new Error('specclaw-budget roles printed no JSON object')
  return Object.entries(doc).sort(([a], [b]) => a.localeCompare(b)).map(([role, r]) => {
    if (!isObject(r) || !['context', 'default', 'min', 'max'].every(k => int(r[k])) || typeof r.source !== 'string') {
      throw new Error(`specclaw-budget roles: role ${role} is not in the expected form`)
    }
    return { role, context: r.context as number, default: r.default as number, min: r.min as number, max: r.max as number, source: r.source }
  })
}

export const parseDismissed = (text: string) => text.split('\n').map(l => l.trim()).filter(Boolean)

// The Bash tool gives no exit code, so the runner prints one after the command's output.
const MARK = '__dash_exit='
export const wrap = (cwd: string, command: string) => `{ cd ${quote(cwd)} && { ${command} ; } ; } 2>&1; echo "${MARK}$?"`
export const unwrap = (stdout: string) => {
  const at = stdout.lastIndexOf(MARK)
  if (at < 0) return { code: -1, out: stdout.trimEnd() } // cut off before the mark: the exit code is unknown
  return { code: Number.parseInt(stdout.slice(at + MARK.length), 10), out: stdout.slice(0, at).trimEnd() }
}

export const CAPS_NOTE = 'Caps need specclaw ≥ the context-gate release (065): specclaw-budget is not installed.'
export const FLEET_SETUP = 'Set up fleet: /plugin install specclaw-fleet@chan4lk, then /specclaw-fleet:setup'

// Exit 127 is the shell's "command not found": say what to install instead of a bare error.
export const hint = (command: string, code: number, out: string) => {
  if (code !== 127) return out
  const name = command.split(' ')[0]
  if (name === 'specclaw-fleet') return `${out}\n${FLEET_SETUP}`
  if (name === 'specclaw-budget') return `${out}\n${CAPS_NOTE}`
  return `${out}\n${name} is not on PATH: /plugin install ${name === 'specclaw-suggest' ? 'specclaw' : name}@chan4lk`
}

// A list command's output as a pane section: not installed is a card, any other failure one error line.
export const listSection = <T>(ran: { code: number | null; out: string }, parse: (out: string) => T, missing: string): Section<T> => {
  if (ran.code === 127) return { kind: 'missing', card: missing }
  if (ran.code !== 0) return { kind: 'error', error: ran.out.split('\n')[0] || `exit ${ran.code}` }
  try {
    return { kind: 'ok', data: parse(ran.out) }
  } catch (error) {
    return { kind: 'error', error: error instanceof Error ? error.message : String(error) }
  }
}
