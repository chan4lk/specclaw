import type { Register } from 'claude-code'
import { bandText, paneLines } from './core/view.ts'
import { notify, readView, refreshQuietly } from './read.ts'

const PANE = 'dash'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'dash', description: 'Show the specclaw build, review and learning loops and token use (read only)' }).catch(() => notify($, 'specclaw-dash: /dash could not be registered.'))
    await refreshQuietly($)
    return next(e)
  })

  on('command.run', { command: 'dash' }, async $ => {
    await refreshQuietly($)
    const opened = await $.ui.open({ id: PANE, title: 'dash' }).then(() => true, () => false)
    if (!opened) await notify($, 'specclaw-dash: the pane could not be opened.')
    return { text: opened ? 'dash pane opened.' : 'dash pane could not be opened.' }
  })

  on('turn.complete', async ($, e, next) => {
    await refreshQuietly($)
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    if (/\.specclaw/i.test(JSON.stringify(e))) await refreshQuietly($)
    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = paneLines(await readView($), await $.clock.now())
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
