import type { Register } from 'claude-code'
import { gateDecision, gateMode, isGateOpen } from './core/gate.ts'
import { bandText, paneLines } from './core/view.ts'
import { placeInCwd } from './place.ts'
import { notify, readView, refresh, refreshQuietly } from './refresh.ts'

const PANE = 'specclaw'

export const register: Register = (on, options) => {
  const { mode, unknown } = gateMode(options.gate)

  on('session.start', async ($, e, next) => {
    if (unknown !== undefined) await notify($, `specclaw: unknown gate mode "${unknown}", using warn. Use warn, block or off.`)
    await $.command.register({ name: 'specclaw-pane', description: 'Show the active specclaw changes in a pane' }).catch(() => notify($, 'specclaw: /specclaw-pane could not be registered.'))
    await refreshQuietly($)
    return next(e)
  })

  on('command.run', { command: 'specclaw-pane' }, async $ => {
    await refreshQuietly($)
    const opened = await $.ui.open({ id: PANE, title: 'specclaw' }).then(() => true, () => false)
    if (!opened) await notify($, 'specclaw: the pane could not be opened.')
    return { text: opened ? 'specclaw pane opened.' : 'specclaw pane could not be opened.' }
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
    const snapshot = await refresh($)
    const placed = isGateOpen(snapshot) ? { root: '/', target: path } : await placeInCwd($, path)
    const verdict = gateDecision({ ...placed, path, mode, snapshot })
    if (verdict.action === 'deny') return { deny: verdict.message }
    if (verdict.action === 'warn') await notify($, verdict.message)
    return next(e)
  }).catch(async ($, e, next) => {
    const failed = 'specclaw: the propose gate failed; the edit was allowed.'
    if (!next.called) await notify($, failed)
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = paneLines(await readView($))
    return <Box flexDirection="column">{lines.map(line => <Text key={line}>{line}</Text>)}</Box>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = bandText(await readView($))
    if (text === undefined || e.props.hasSurvey) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>{text}</Text>
  })
}
