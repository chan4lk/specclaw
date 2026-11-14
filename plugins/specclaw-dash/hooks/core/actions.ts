// Each pane action as the one existing command it runs, and the parsers for what those commands print. Pure.
// The pane owns no logic: specclaw-fleet, specclaw-review, specclaw-budget (065) and specclaw-suggest decide.
import type { CapRow, ChangeRow } from '../../types/index.d.ts'

// Every value put into a command must match its pattern, or the action is refused before a command exists.
const CHANGE = /^\d{3}-[a-z0-9][a-z0-9-]*$/
const PATTERNS = {
  'feature module': /^[a-z][a-z0-9_-]*$/,
  fingerprint: /^[0-9a-f]{6,64}$/,
  role: /^[a-z][a-z0-9_-]*$/,
  number: /^\d{1,9}$/,
  feature: /^[a-z]+$/,
} as const

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

// `optin --dry-run` prints one `<item>: …` line per item. Only `would …` and `already opted in by …` can
// launch; `refused: assigned to …` (someone else's) and any error cannot. No line for any item means fleet
// could not run at all (not set up, no token), and nothing is launchable.
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
export const wrap = (cwd: string, command: string) => `cd ${quote(cwd)} && { ${command} ; } 2>&1; echo "${MARK}$?"`
export const unwrap = (stdout: string) => {
  const at = stdout.lastIndexOf(MARK)
  if (at < 0) return { code: -1, out: stdout.trimEnd() } // cut off before the mark: the exit code is unknown
  return { code: Number.parseInt(stdout.slice(at + MARK.length), 10), out: stdout.slice(0, at).trimEnd() }
}
