import { expect, test } from 'claude-code/testing'
import { DONE, LIVE, NOW, doc } from './fixtures.ts'

const SNAPSHOT = '/x/.specclaw/fleet/report.json'
const PANE = { plugin: 'specclaw-fleet', component: 'Pane', requestId: 'specclaw-fleet', surface: 'terminal',
  props: { title: 'fleet build', isFocused: false, bodyColumns: 90, placement: 'dock', scroll: { offset: 0, bodyRows: 30 }, view: {} } } as const
const BAND = { plugin: 'specclaw-fleet', component: 'AbovePrompt', surface: 'terminal',
  props: { hasSurvey: false, isWorking: false, maxRows: 4, bodyColumns: 90, scroll: { offset: 0, bodyRows: 4 }, view: {} } } as const

const engine = (on: Parameters<Parameters<typeof test>[1]>[1], files: Record<string, string>, statuses: (string | undefined)[], runs = { n: 0 }) => {
  on('session.cwd', () => ({ value: '/x' }))
  on('clock.now', () => ({ value: NOW }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => ({ value: files[e.path] }))
  on('ui.status', (_, e) => (statuses.push(e.text), { value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('tool.call', () => (runs.n += 1, { result: { ok: true } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

test('R054 AC-5 /fleet-pane opens and renders the seeded snapshot', async ($, on) => {
  const statuses: (string | undefined)[] = []
  engine(on, { [SNAPSHOT]: doc([DONE, LIVE], { prs_open: 0 }) }, statuses)
  const ran = await $.command.run({ command: 'fleet-pane', args: '' })
  expect((ran as { text: string }).text).toBe('fleet pane opened. Refresh with: specclaw-fleet report --save')
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /^fleet build · latest/ }))?.text).toMatch(/snapshot/)
  expect((await ui.find({ type: 'Text', text: /^003-detail .*running/ }))?.text).toContain('2')
  expect(statuses.at(-1)).toBe('fleet: 1 running')
  await ui.unmount()
})

const CALLS: [string, string, boolean][] = [
  ['report --save', 'specclaw-fleet report --save', true],
  ['status', 'cd repo && specclaw-fleet status 003-detail', true],
  ['trigger', 'specclaw-fleet  trigger 003-detail', true],
  ['unrelated', 'specclaw-fleet doctor', false],
  ['mention only', 'echo specclaw-fleet-report', false],
]

for (const [why, command, refreshes] of CALLS) {
  test(`R054 AC-5 Bash ${why} ${refreshes ? 'refreshes' : 'does not refresh'} the band`, async ($, on) => {
    const files: Record<string, string> = {}
    const statuses: (string | undefined)[] = []
    engine(on, files, statuses)
    files[SNAPSHOT] = doc([LIVE])
    await $.tool.call({ tool: 'Bash', command })
    const ui = await $.ui.mount(BAND)
    const band = await ui.find({ type: 'Text', text: /^fleet ·/ })
    expect([band?.text, statuses.at(-1)]).toEqual(refreshes ? ['fleet · 1 running · 0 PRs open · last run 11:53 UTC', 'fleet: 1 running'] : [undefined, undefined])
    await ui.unmount()
  })
}

test('R054 AC-5 a refresh that fails after a fleet command never reruns it or throws', async ($, on) => {
  const runs = { n: 0 }
  engine(on, { [SNAPSHOT]: doc([LIVE]) }, [], runs)
  on('state.set', () => { throw new Error('state.set throws') })
  const ran = await $.tool.call({ tool: 'Bash', command: 'specclaw-fleet report --save' })
  expect([runs.n, ran]).toEqual([1, { result: { ok: true } }])
})
