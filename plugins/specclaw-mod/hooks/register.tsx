import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { gateDecision, type GateMode } from './core/gate.ts'
import type { Snapshot } from './core/state.ts'
import { bandText, paneLines, statusText } from './core/view.ts'
import { placeInCwd } from './place.ts'
import { readSnapshot } from './read.ts'

const PANE = 'specclaw'
const EMPTY: Snapshot = { hasSpecclaw: false, changes: [] }
const UNREADABLE: Snapshot = { hasSpecclaw: true, isUnreadable: true, changes: [] }
const snapshot = atom({ plugin: 'specclaw-mod', key: 'snapshot' } as const, EMPTY, { shape: 'snapshot-2' })

async function refresh($: EngineInterface) {
  const latest = await readSnapshot($, await $.session.cwd())
  await update($, snapshot, () => latest)
  $.ui.status(statusText(latest))
  return latest
}

async function refreshQuietly($: EngineInterface) {
  await refresh($).catch(() => {
    $.ui.status(statusText(UNREADABLE))
    return update($, snapshot, () => UNREADABLE).catch(() => undefined)
  })
}

export const register: Register = (on, options) => {
  const mode = (options.gate ?? 'block') as GateMode

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'specclaw-pane', description: 'Show the active specclaw changes in a pane' })
    await refreshQuietly($)
    return next(e)
  })

  on('command.run', { command: 'specclaw-pane' }, async $ => {
    await refreshQuietly($)
    await $.ui.open({ id: PANE, title: 'specclaw' })
    return { text: 'specclaw pane opened.' }
  })

  on('turn.complete', async ($, e, next) => {
    await refreshQuietly($)
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (/\.specclaw/i.test(JSON.stringify(e))) await refreshQuietly($)
    return ran
  })

  on('tool.call', { tool: ['Edit', 'Write', 'NotebookEdit'] }, async ($, e, next) => {
    if (mode === 'off') return next(e)
    const path = 'notebook_path' in e ? e.notebook_path : e.file_path
    const { root, target } = await placeInCwd($, path)
    const verdict = gateDecision({ root, target, path, mode, snapshot: await refresh($) })
    if (verdict.action === 'deny') return { deny: verdict.message }
    if (verdict.action === 'warn') $.ui.toast(verdict.message)
    return next(e)
  }).catch(($, e, next) => {
    if (!next.called) $.ui.toast('specclaw: the propose gate failed; the edit was allowed.')
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = paneLines(await read($, snapshot))
    return <Box flexDirection="column">{lines.map(line => <Text key={line}>{line}</Text>)}</Box>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = bandText(await read($, snapshot))
    if (text === undefined || e.props.hasSurvey) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{text}</Text>
  })
}
