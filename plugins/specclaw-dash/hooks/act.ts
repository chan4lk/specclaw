// The one place the mod runs a command: through the Bash tool, so plugin bin/ folders are on PATH and the
// session's permission rules decide. A call the rules do not allow goes into the prompt for the person to send.
import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { Actions, Ran } from '../types/index.d.ts'
import { hint, unwrap, wrap } from './core/actions.ts'
import { refreshQuietly } from './read.ts'

const NONE: Actions = { selected: [], plan: null, last: null, caps: null, dismissed: null }
const actions = atom({ plugin: 'specclaw-dash', key: 'actions' } as const, NONE, { shape: 'dash-actions-1' })

export async function readActions($: EngineInterface) {
  return read($, actions)
}
export async function updateActions($: EngineInterface, fn: (a: Actions) => Actions) {
  await update($, actions, fn)
}

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

async function run($: EngineInterface, command: string): Promise<Ran> {
  const cwd = await $.session.cwd()
  const r = await $.tool.call({ tool: 'Bash', command: wrap(cwd, command), description: `specclaw-dash: ${command.split(' ')[0]}`, timeout: 600000 })
  if (r.deny !== undefined) {
    const filled = await $.prompt.fill({ text: command }).then(f => f.isFilled, () => false)
    return { command, code: null, out: `Not allowed to run from the pane (${r.deny}). ${filled ? 'The command is in the prompt: send it to run it.' : `Run it yourself: ${command}`}` }
  }
  const result = r.result as { stdout?: unknown } | undefined
  if (r.isError || typeof result?.stdout !== 'string') return { command, code: -1, out: r.text ?? 'the command failed to run' }
  const { code, out } = unwrap(result.stdout)
  return { command, code, out: hint(command, code, out) }
}

// Builds the command (a refused value throws here, before anything runs), runs it, keeps what `then` derives
// from the result, records it as the last action unless `quiet`, then re-reads the pane.
export async function act($: EngineInterface, build: () => string, then?: (ran: Ran) => Partial<Actions>, quiet = false) {
  let ran: Ran
  try {
    ran = await run($, build())
  } catch (error) {
    ran = { command: '', code: -1, out: message(error) }
  }
  const derived = then?.(ran) ?? {}
  await update($, actions, a => ({ ...a, ...derived, ...(quiet && ran.code === 0 ? {} : { last: ran }) }))
  await refreshQuietly($)
  return ran
}
