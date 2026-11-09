import type { Register } from 'claude-code'
import { bandText, paneLines } from './core/view.ts'
import { notify, readView, refreshQuietly } from './snapshot.ts'

const PANE = 'specclaw-fleet'
const FLEET_CALL = /specclaw-fleet\s+(trigger|status|report)\b/

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'fleet-pane', description: 'Show the latest specclaw-fleet build: timeline, lifecycle and totals' }).catch(() => notify($, 'specclaw-fleet: /fleet-pane could not be registered.'))
    await refreshQuietly($)
    return next(e)
  })

  on('command.run', { command: 'fleet-pane' }, async $ => {
    await refreshQuietly($)
    const opened = await $.ui.open({ id: PANE, title: 'fleet build' }).then(() => true, () => false)
    if (!opened) await notify($, 'specclaw-fleet: the pane could not be opened.')
    return { text: opened ? 'fleet pane opened. Refresh with: specclaw-fleet report --save' : 'fleet pane could not be opened.' }
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (FLEET_CALL.test(e.command)) await refreshQuietly($)
    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = paneLines(await readView($), await $.clock.now(), e.props.bodyColumns)
    return <Box flexDirection="column">{lines.map((line, i) => <Text key={`${i}`}>{line || ' '}</Text>)}</Box>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const text = bandText(await readView($))
    if (text === undefined || e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const below = await next(e)
    const band = <Text dimColor>{text}</Text>
    return below ? <Box flexDirection="column">{below}{band}</Box> : band
  })
}
