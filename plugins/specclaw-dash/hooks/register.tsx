import type { EngineInterface, Register } from 'claude-code'
import type { Actions, DashView, RuleRow, Section } from '../types/index.d.ts'
import { CAPS_NOTE, FLEET_SETUP, commands, dryRunResult, launchItems, listSection, parseCaps, parseDismissed } from './core/actions.ts'
import { bandText, paneLines } from './core/view.ts'
import { act, readActions, updateActions } from './act.ts'
import { notify, readView, refreshQuietly } from './read.ts'

const PANE = 'dash'

const specclawDir = async ($: EngineInterface) => `${await $.session.cwd()}/.specclaw`

// Launch: a dry run first, of exactly the selection; Confirm only for the items it did not refuse.
async function dryRun($: EngineInterface) {
  const items = (await readActions($)).selected
  await act($, () => commands.dryRun(items), ran => {
    if (ran.code === null || ran.code === 127) return { plan: null }
    const { launchable, named } = dryRunResult(items, ran.out)
    if (named === 0 && ran.code > 0) ran.out = `${ran.out}\nFleet could not run. ${FLEET_SETUP}` // not a timeout (-1)
    return { plan: { items, launchable } }
  })
}

async function launch($: EngineInterface) {
  const { plan, selected } = await readActions($)
  if (!plan || plan.launchable.length === 0 || plan.items.join(' ') !== selected.join(' ')) return
  await updateActions($, s => ({ ...s, selected: [], plan: null })) // first, so a second press cannot launch twice
  await act($, () => commands.launch(plan.launchable))
}

const loadCaps = ($: EngineInterface) => specclawDir($).then(dir => act($, () => commands.caps(dir), ran => ({ caps: listSection(ran, parseCaps, CAPS_NOTE) }), true))
const loadDismissed = ($: EngineInterface) => specclawDir($).then(dir =>
  act($, () => commands.dismissed(dir), ran => ({ dismissed: listSection(ran, parseDismissed, 'specclaw-suggest is not on PATH: /plugin install specclaw@chan4lk') }), true))

function Actions$($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0], view: DashView, a: Actions) {
  const { Box, Text, Button, Input } = $.ui.resolve(e)
  const items = view.build.kind === 'ok' ? launchItems(view.build.data.changes) : []
  const rules: Section<RuleRow[]> = view.learning.kind === 'ok' ? view.learning.data.proposed : { kind: 'missing', card: '' }
  const planned = a.plan && a.plan.items.join(' ') === a.selected.join(' ') ? a.plan : null
  const toggle = (item: string) => updateActions($, s => ({
    ...s, plan: null, selected: s.selected.includes(item) ? s.selected.filter(i => i !== item) : [...s.selected, item],
  }))
  const off = (s: Section<unknown> | null) => (s === null ? [] : s.kind === 'missing' ? [<Text>{`  ${s.card}`}</Text>] : s.kind === 'error' ? [<Text>{`  error: ${s.error}`}</Text>] : [])
  return (
    <Box flexDirection="column">
      <Text>ACTIONS · each runs an existing command through the Bash tool</Text>
      <Text>  Launch with specclaw-fleet: only work items assigned to you and tagged fleet:auto by you</Text>
      {items.length === 0 ? <Text>  No approved changes or features to launch.</Text> : (
        <Box flexDirection="row" flexWrap="wrap">
          {items.map(i => <Button key={`pick-${i}`} label={`${a.selected.includes(i) ? '[x]' : '[ ]'} ${i}`} onPress={() => void toggle(i)} />)}
        </Box>
      )}
      {a.selected.length > 0 && <Button key="dry-run" label={`Dry run (${a.selected.length} selected)`} onPress={() => void dryRun($)} />}
      {planned && <Text>{`  dry run: ${planned.launchable.length} of ${planned.items.length} can launch${planned.launchable.length ? `: ${planned.launchable.join(' ')}` : ''}`}</Text>}
      {planned && planned.launchable.length > 0 && (
        <Box flexDirection="row">
          <Button key="confirm-launch" variant="primary" label={`Confirm: launch ${planned.launchable.length} (spends your plan, pushes a branch)`} onPress={() => void launch($)} />
          <Button key="cancel-launch" label="Cancel" onPress={() => void updateActions($, s => ({ ...s, plan: null }))} />
        </Box>
      )}
      <Text>  Proposed rules</Text>
      {rules.kind === 'ok' && rules.data.length === 0 && <Text>  None awaiting approval.</Text>}
      {rules.kind === 'ok' && rules.data.map(r => (
        <Box key={`rule-${r.fp}`} flexDirection="row">
          <Text>{`  ${r.lesson} (seen ${r.seen}x) `}</Text>
          <Button key={`approve-${r.fp}`} label="Approve" onPress={() => void act($, () => commands.approve(r.fp))} />
          <Button key={`reject-${r.fp}`} label="Reject" onPress={() => void act($, () => commands.reject(r.fp))} />
        </Box>
      ))}
      {rules.kind !== 'ok' && <Text>  See LEARNING above.</Text>}
      <Text>  Context caps</Text>
      <Button key="show-caps" label={a.caps ? 'Reload caps' : 'Show caps'} onPress={() => void loadCaps($)} />
      {off(a.caps)}
      {a.caps?.kind === 'ok' && a.caps.data.map(c => (
        <Box key={`cap-row-${c.role}`} flexDirection="row">
          <Text>{`  ${c.role.padEnd(14)} ${c.context} (${c.min}–${c.max}, default ${c.default}, ${c.source}) `}</Text>
          <Input key={`cap-${c.role}`} placeholder="new cap, Enter" submitLabel="set" onSubmit={value => void specclawDir($).then(dir => act($, () => commands.setCap(dir, c.role, value)).then(() => loadCaps($)))} />
        </Box>
      ))}
      <Text>  Dismissed suggestions</Text>
      <Button key="show-dismissed" label={a.dismissed ? 'Reload dismissed' : 'Show dismissed'} onPress={() => void loadDismissed($)} />
      {off(a.dismissed)}
      {a.dismissed?.kind === 'ok' && a.dismissed.data.length === 0 && <Text>  None dismissed.</Text>}
      {a.dismissed?.kind === 'ok' && a.dismissed.data.map(f => (
        <Box key={`dismissed-${f}`} flexDirection="row">
          <Text>{`  ${f} `}</Text>
          <Button key={`undo-${f}`} label="Undo" onPress={() => void specclawDir($).then(dir => act($, () => commands.undismiss(dir, f)).then(() => loadDismissed($)))} />
        </Box>
      ))}
      {a.last && <Text>{`  last: ${a.last.command || '(refused)'} · ${a.last.code === null ? 'sent to the prompt' : `exit ${a.last.code}`}`}</Text>}
      {a.last && a.last.out.split('\n').slice(-12).map(line => <Text dimColor>{`    ${line}`}</Text>)}
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'dash', description: 'Show the specclaw loops and token use, and launch, approve and edit caps' }).catch(() => notify($, 'specclaw-dash: /dash could not be registered.'))
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

  // Tools that can change .specclaw: a read never does, and turn.complete refreshes anyway.
  on('tool.call', { tool: ['Bash', 'Edit', 'Write', 'NotebookEdit'] }, async ($, e, next) => {
    const ran = await next(e)
    if (/\.specclaw/i.test(JSON.stringify(e))) await refreshQuietly($)
    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const view = await readView($)
    const lines = paneLines(view, await $.clock.now())
    return (
      <Box flexDirection="column">
        {lines.map((line, i) => <Text key={`${i}`}>{line || ' '}</Text>)}
        <Text> </Text>
        {Actions$($, e, view, await readActions($))}
      </Box>
    )
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
