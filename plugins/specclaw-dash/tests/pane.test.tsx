import { expect, test } from 'claude-code/testing'
import { NOW, assistant, lines, title } from './fixtures.ts'

const PANE = { plugin: 'specclaw-dash', component: 'Pane', requestId: 'dash', surface: 'terminal',
  props: { title: 'dash', isFocused: false, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} } } as const
const BAND = { plugin: 'specclaw-dash', component: 'AbovePrompt', surface: 'terminal',
  props: { hasSurvey: false, isWorking: false, maxRows: 4, bodyColumns: 120, scroll: { offset: 0, bodyRows: 4 }, view: {} } } as const

const C = '/x/.specclaw/changes/062-x'
const T = '/h/.claude/projects/-x'
const MAIN = lines(title('custom-title', 'Build 062'), assistant('m1', '2026-11-14T09:00:00Z', { input: 1000, output: 1000 }))
const SUB = lines(assistant('s1', '2026-11-14T09:30:00Z', { output: 1000 }, 'claude-sonnet-5-5'))

const seed = () => ({
  '/x/.specclaw': null,
  '/x/.specclaw/changes': null,
  [C]: null,
  [`${C}/state.json`]: JSON.stringify({ phase: 'build', phases: {} }),
  [`${C}/tasks.md`]: '- [x] `T1` — a\n- [ ] `T2` — b\n',
  [`${C}/timeline.jsonl`]: '{"ev":"start","span":"W1","label":"wave 1","ts":1794650400}\n{"kind":"lesson","at":"2026-11-14T10:00:00Z","category":"pattern","priority":"high","detail":"say hi","action":"a"}\n',
  [`${C}/review`]: null,
  [`${C}/review/round-1.json`]: JSON.stringify({ round: 1, status: 'clean', final: true, head: 'abc1234', counts: { blocker: 0, major: 1, minor: 2 }, escalated: ['f'] }),
  '/x/.git': null,
  '/x/.git/HEAD': 'abc1234\n',
  [T]: null,
  [`${T}/s1.jsonl`]: MAIN,
  [`${T}/s1`]: null,
  [`${T}/s1/subagents`]: null,
  [`${T}/s1/subagents/agent-a1.jsonl`]: SUB,
  [`${T}/s1/subagents/agent-a1.meta.json`]: JSON.stringify({ agentType: 'code-reviewer', description: 'r' }),
} as Record<string, string | null>)

type Calls = { reads: string[]; writes: number; mcp: number }
type Link = { isConnected: true; server: string } | { isConnected: false; reason: string; message: string }
const LINKED: Link = { isConnected: true, server: 'plugin:specclaw-review:specclaw-review' }

const engine = (on: Parameters<Parameters<typeof test>[1]>[1], files: Record<string, string | null>, statuses: (string | undefined)[], calls: Calls, mcp: () => unknown, link: Link = LINKED) => {
  on('mcp.connect', () => ({ value: link }))
  on('session.cwd', () => ({ value: '/x' }))
  on('clock.now', () => ({ value: NOW }))
  on('env.get', (_, e) => ({ value: e.name === 'HOME' ? '/h' : undefined }))
  on('fs.exists', (_, e) => ({ value: e.path in files }))
  on('fs.read', (_, e) => {
    calls.reads.push(e.path)
    const text = files[e.path]
    if (typeof text !== 'string') throw new Error(`no file ${e.path}`)
    return { value: text }
  })
  on('fs.list', (_, e) => ({
    value: Object.keys(files).filter(p => p.startsWith(`${e.path}/`) && !p.slice(e.path.length + 1).includes('/')).map(p => ({
      name: p.slice(e.path.length + 1), kind: files[p] === null ? 'dir' : 'file', size: (files[p] ?? '').length, mtimeMs: files[p] === null ? 0 : NOW - 1000, isLink: false,
    })),
  }))
  on('fs.stat', (_, e) => {
    if (!(e.path in files)) throw new Error(`no file ${e.path}`)
    return { value: { kind: files[e.path] === null ? 'dir' : 'file', size: (files[e.path] ?? '').length, mtimeMs: NOW - 1000, isLink: false } }
  })
  on('fs.write', () => { calls.writes += 1; return { value: undefined } })
  on('mcp.call', () => { calls.mcp += 1; return mcp() })
  on('ui.status', (_, e) => (statuses.push(e.text), { value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
}

const FP = '0a1b2c3d4e5f'
const RULES = () => ({ value: { content: [{ type: 'text', text: `2 proposed rule(s) for .specclaw/review/rules/learned.md (dry-run):\n\n- fp ${FP} [major B3] seen 3x in a.py: guard nulls\n- fp 99aa88bb77cc [minor S1] seen 4x in b.ts: name it` }], isError: false } })

test('R062 AC-6 /dash opens the pane and draws every part from the files', async ($, on) => {
  const statuses: (string | undefined)[] = []
  const calls = { reads: [], writes: 0, mcp: 0 }
  engine(on, seed(), statuses, calls, RULES)
  const ran = await $.command.run({ command: 'dash', args: '' })
  expect((ran as { text: string }).text).toBe('dash pane opened.')
  const ui = await $.ui.mount(PANE)
  const has = async (text: RegExp) => (await ui.find({ type: 'Text', text }))?.text
  expect(await has(/^ {2}062-x/)).toMatch(/build +1\/2 +wave 1/)
  expect(await has(/rounds/)).toBe('  062-x                        1 rounds · clean · last 0/1/2 b/M/m · 1 escalated · final abc1234 at HEAD')
  expect(await has(/proposed rules/)).toBe('  2 proposed rules awaiting approval (approve or reject under ACTIONS)')
  expect(await has(/^ {2}1 lessons/)).toBe('  1 lessons · pattern 1')
  expect(await has(/^TOKENS/)).toContain('API-equivalent estimate')
  expect(await has(/by role/)).toBe('  by role: main $0.02 · code-reviewer $0.01')
  expect(await has(/fleet/)).toMatch(/^ {2}fleet: no report\. Install specclaw-fleet/)
  expect(statuses.at(-1)).toBe('dash: 1 building · $0.03 today (API-equivalent estimate)')
  expect(calls.writes).toBe(0)
  await ui.unmount()
  const band = await $.ui.mount(BAND)
  expect((await band.find({ type: 'Text', text: /^dash ·/ }))?.text).toBe('dash · 1 building · 0 in review · $0.03 today, API-equivalent estimate')
  await band.unmount()
})

test('R062 AC-3 a second refresh with unchanged transcripts reads none of them again', async ($, on) => {
  const calls: Calls = { reads: [], writes: 0, mcp: 0 }
  engine(on, seed(), [], calls, RULES)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.command.run({ command: 'dash', args: '' })
  const first = calls.reads.filter(p => p.endsWith('.jsonl') && p.startsWith(T)).length
  await $.turn.complete({ answer: 'a', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' })
  expect([first, calls.reads.filter(p => p.endsWith('.jsonl') && p.startsWith(T)).length]).toEqual([2, 2])
})

const LINKS: [string, Link, () => unknown, RegExp, RegExp][] = [
  ['not installed', { isConnected: false, reason: 'unlisted', message: 'no such server' }, RULES,
    /^ {2}Review loop: no rounds yet\. Install specclaw-review/, /^ {2}Proposed rules: specclaw-review is not installed/],
  ['failed to connect', { isConnected: false, reason: 'failed', message: 'crashed' }, RULES,
    /^ {2}No review rounds in the active changes\./, /^ {2}error: specclaw-review not connected \(failed\): crashed/],
  ['call throws (timeout)', LINKED, () => { throw new Error('timeout') }, /^ {2}No review rounds/, /^ {2}error: learn_propose failed/],
  ['tool error', LINKED, () => ({ value: { content: [{ type: 'text', text: 'boom' }], isError: true } }), /^ {2}No review rounds/, /^ {2}error: learn_propose failed: boom/],
]

for (const [why, link, mcp, review, rules] of LINKS) {
  test(`R062 AC-5 no rounds and specclaw-review ${why}: only "not installed" is an install card`, async ($, on) => {
    const files = seed()
    delete files[`${C}/review/round-1.json`]
    engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, mcp, link)
    await $.command.run({ command: 'dash', args: '' })
    const ui = await $.ui.mount(PANE)
    expect((await ui.find({ type: 'Text', text: review }))?.text).toBeDefined()
    expect((await ui.find({ type: 'Text', text: rules }))?.text).toBeDefined()
    await ui.unmount()
  })
}

test('R062 AC-5 no .specclaw and no transcripts: install cards, no band', async ($, on) => {
  const statuses: (string | undefined)[] = []
  engine(on, {}, statuses, { reads: [], writes: 0, mcp: 0 }, RULES)
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /No \.specclaw/ }))?.text).toBe('  No .specclaw/ in this project. Install specclaw: /plugin install specclaw@chan4lk')
  expect((await ui.find({ type: 'Text', text: /transcripts at/ }))?.text).toBe('  No Claude Code transcripts at /h/.claude/projects/-x')
  await ui.unmount()
  const band = await $.ui.mount(BAND)
  expect(await band.find({ type: 'Text', text: /^dash ·/ })).toBeUndefined()
  expect(statuses.at(-1)).toBeUndefined()
  await band.unmount()
})

test('R062 AC-5 a failed read shows an error line, never numbers', async ($, on) => {
  const files = seed()
  files[`${C}/state.json`] = null // a folder where state.json should be: the read throws
  engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, RULES)
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  expect((await ui.find({ type: 'Text', text: /^ {2}error:/ }))?.text).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /rounds/ })).toBeUndefined()
  await ui.unmount()
})

const META = `${T}/s1/subagents/agent-a1.meta.json`
const GOOD = JSON.stringify({ agentType: 'code-reviewer', description: 'r' })
const roleLine = async (ui: { find: (q: object) => Promise<{ text?: string } | undefined> }) => (await ui.find({ type: 'Text', text: /by role/ }))?.text
const turn = { answer: 'a', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' } as const

// Each bad meta reads as "subagent" and is asked again: once it is good, the next refresh shows its type.
const METAS: [string, (files: Record<string, string | null>) => void][] = [
  ['absent', files => { delete files[META] }],
  ['a read that throws', files => { files[META] = null }],
  ['malformed JSON', files => { files[META] = '{' }],
  ['JSON without agentType', files => { files[META] = '{"description":"r"}' }],
]
for (const [why, spoil] of METAS) {
  test(`R062 AC-2 a subagent meta that is ${why} is read again, never cached as "subagent"`, async ($, on) => {
    const files = seed()
    spoil(files)
    engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, RULES)
    on('turn.complete', (_, e) => ({ text: e.answer }))
    await $.command.run({ command: 'dash', args: '' })
    const ui = await $.ui.mount(PANE)
    expect(await roleLine(ui)).toBe('  by role: main $0.02 · subagent $0.01')
    files[META] = GOOD
    await $.turn.complete(turn)
    expect(await roleLine(ui)).toBe('  by role: main $0.02 · code-reviewer $0.01')
    await ui.unmount()
  })
}

test('R062 AC-2 a parsed role is not read again; a transcript that leaves and returns is asked again', async ($, on) => {
  const files = seed()
  const calls: Calls = { reads: [], writes: 0, mcp: 0 }
  engine(on, files, [], calls, RULES)
  on('turn.complete', (_, e) => ({ text: e.answer }))
  await $.command.run({ command: 'dash', args: '' })
  await $.turn.complete(turn)
  expect(calls.reads.filter(p => p === META).length).toBe(1)
  const sub = files[`${T}/s1/subagents/agent-a1.jsonl`]!
  delete files[`${T}/s1/subagents/agent-a1.jsonl`]
  await $.turn.complete(turn)
  files[`${T}/s1/subagents/agent-a1.jsonl`] = sub
  files[META] = JSON.stringify({ agentType: 'explorer' })
  await $.turn.complete(turn)
  const ui = await $.ui.mount(PANE)
  expect(await roleLine(ui)).toBe('  by role: main $0.02 · explorer $0.01')
  await ui.unmount()
})

// 063: the actions. The test's Bash hook stands for the shell: it records each command and answers by it.
type Answer = { stdout: string } | { deny: string }
const shell = (on: Parameters<Parameters<typeof test>[1]>[1], answer: (command: string) => Answer) => {
  const ran: string[] = []
  on('tool.call', (_, e) => {
    const inner = /^\{ cd '\/x' && \{ (.*) ; \} ; \} 2>&1; echo "__dash_exit=\$\?"$/.exec(String((e as { command?: unknown }).command))
    if (e.tool !== 'Bash' || !inner) throw new Error(`unexpected tool call ${JSON.stringify(e)}`)
    ran.push(inner[1]!)
    const a = answer(inner[1]!)
    return 'deny' in a ? a : { result: { stdout: a.stdout, stderr: '', interrupted: false } }
  })
  return ran
}
const approved = (files: Record<string, string | null>, name: string) => {
  files[`/x/.specclaw/changes/${name}`] = null
  files[`/x/.specclaw/changes/${name}/state.json`] = JSON.stringify({ phase: 'tasks', phases: { proposal: { status: 'approved' } } })
}

test('R063 AC-3 Confirm launch appears only after a dry run of the selection, and launches only what it did not refuse', async ($, on) => {
  const files = seed()
  approved(files, '063-y')
  approved(files, '064-z')
  engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, RULES)
  const ran = shell(on, c => ({ stdout: c.endsWith('--dry-run')
    ? `063-y: would assign to me@x.com and add fleet:auto as me@x.com\n064-z: refused: assigned to o@x.com; only they can opt in\n__dash_exit=4\n`
    : 'queued\n__dash_exit=0\n' }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  const confirm = () => ui.find({ key: 'confirm-launch' })
  expect(await ui.find({ key: 'pick-062-x' })).toBeUndefined()
  await ui.press({ key: 'pick-063-y' })
  await ui.press({ key: 'pick-064-z' })
  expect(await confirm()).toBeUndefined()
  await ui.press({ key: 'dry-run' })
  expect(ran).toEqual(['specclaw-fleet optin 063-y 064-z --dry-run'])
  expect((await confirm())?.text).toContain('Confirm: launch 1 (spends your plan, pushes a branch)')
  await ui.press({ key: 'pick-064-z' })
  expect(await confirm()).toBeUndefined()
  await ui.press({ key: 'pick-064-z' })
  await ui.press({ key: 'dry-run' })
  await ui.press({ key: 'confirm-launch' })
  expect(ran.at(-1)).toBe('specclaw-fleet optin 063-y && specclaw-fleet trigger 063-y')
  expect(await confirm()).toBeUndefined()
  await ui.unmount()
})

test('R063 AC-3 two presses of Confirm at once launch once', async ($, on) => {
  const files = seed()
  approved(files, '063-y')
  engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, RULES)
  const ran = shell(on, c => ({ stdout: c.endsWith('--dry-run') ? '063-y: would assign to me@x.com and add fleet:auto as me@x.com\n__dash_exit=0\n' : 'queued\n__dash_exit=0\n' }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'pick-063-y' })
  await ui.press({ key: 'dry-run' })
  await Promise.allSettled([ui.press({ key: 'confirm-launch' }), ui.press({ key: 'confirm-launch' })])
  expect(ran.filter(c => c.startsWith('specclaw-fleet optin 063-y &&'))).toHaveLength(1)
  await ui.unmount()
})

test('R063 AC-3 fleet not installed or not set up: setup steps, no Confirm', async ($, on) => {
  const files = seed()
  approved(files, '063-y')
  engine(on, files, [], { reads: [], writes: 0, mcp: 0 }, RULES)
  let out = 'bash: specclaw-fleet: command not found\n__dash_exit=127\n'
  shell(on, () => ({ stdout: out }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'pick-063-y' })
  await ui.press({ key: 'dry-run' })
  expect((await ui.find({ type: 'Text', text: /Set up fleet/ }))?.text).toBe('    Set up fleet: /plugin install specclaw-fleet@chan4lk, then /specclaw-fleet:setup')
  expect(await ui.find({ key: 'confirm-launch' })).toBeUndefined()
  // No item named: exit 1 (no token) and exit 0 (unknown output) point at setup; a cut-off run (no exit mark) says so.
  for (const [o, said] of [['no token\n__dash_exit=1\n', /Fleet could not run/], ['changed format\n__dash_exit=0\n', /Fleet could not run/],
    ['cut off', /did not finish \(timeout or cut-off output\)/]] as const) {
    out = o
    await ui.press({ key: 'dry-run' })
    expect((await ui.find({ type: 'Text', text: said }))?.text).toBeDefined()
    expect(await ui.find({ key: 'confirm-launch' })).toBeUndefined()
  }
  await ui.unmount()
})

test('R063 AC-4 a Bash call the permission rules refuse puts the exact command into the prompt', async ($, on) => {
  engine(on, seed(), [], { reads: [], writes: 0, mcp: 0 }, RULES)
  const filled: string[] = []
  on('prompt.fill', (_, e) => (filled.push(e.text), { isFilled: true }))
  shell(on, () => ({ deny: 'no rule allows it' }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: `approve-${FP}` })
  expect(filled).toEqual([`specclaw-review learn --apply ${FP}`])
  expect((await ui.find({ type: 'Text', text: /^ {2}last:/ }))?.text).toBe(`  last: specclaw-review learn --apply ${FP} · sent to the prompt`)
  await ui.unmount()
})

const CAPS = '{"coding":{"context":120000,"default":120000,"min":40000,"max":400000,"source":"default"}}'

test('R063 AC-5 approve, reject, caps and undo each run their command; the pane never writes a file', async ($, on) => {
  const calls: Calls = { reads: [], writes: 0, mcp: 0 }
  engine(on, seed(), [], calls, RULES)
  const ran = shell(on, c => ({ stdout: `${c.startsWith('specclaw-budget roles') ? CAPS : c.endsWith('--dismissed') ? 'fleet' : 'ok'}\n__dash_exit=0\n` }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: `approve-${FP}` })
  await ui.press({ key: 'reject-99aa88bb77cc' })
  await ui.press({ key: 'show-caps' })
  expect((await ui.find({ type: 'Text', text: /^ {2}coding/ }))?.text).toContain('120000 (40000–400000, default 120000, default)')
  await ui.input({ key: 'cap-coding', text: '90000' })
  await ui.press({ key: 'show-dismissed' })
  await ui.press({ key: 'undo-fleet' })
  expect(ran).toEqual([
    `specclaw-review learn --apply ${FP}`, 'specclaw-review learn --reject 99aa88bb77cc',
    "specclaw-budget roles --json '/x/.specclaw'", "specclaw-budget set '/x/.specclaw' coding 90000", "specclaw-budget roles --json '/x/.specclaw'",
    "specclaw-suggest '/x/.specclaw' --dismissed", "specclaw-suggest '/x/.specclaw' --undismiss fleet", "specclaw-suggest '/x/.specclaw' --dismissed",
  ])
  expect(calls.writes).toBe(0)
  await ui.unmount()
})

test('R063 AC-5 no specclaw-budget: the 065 note and no cap input; a bad cap is refused before any command', async ($, on) => {
  engine(on, seed(), [], { reads: [], writes: 0, mcp: 0 }, RULES)
  let budget = false
  const ran = shell(on, c => ({ stdout: budget && c.startsWith('specclaw-budget roles') ? `${CAPS}\n__dash_exit=0\n` : 'bash: specclaw-budget: command not found\n__dash_exit=127\n' }))
  await $.command.run({ command: 'dash', args: '' })
  const ui = await $.ui.mount(PANE)
  await ui.press({ key: 'show-caps' })
  expect((await ui.find({ type: 'Text', text: /context-gate/ }))?.text).toBe('  Caps need specclaw ≥ the context-gate release (065): specclaw-budget is not installed.')
  expect(await ui.find({ key: 'cap-coding' })).toBeUndefined()
  budget = true
  await ui.press({ key: 'show-caps' })
  await ui.input({ key: 'cap-coding', text: '9e4; rm -rf ~' })
  expect(ran.filter(c => c.startsWith('specclaw-budget set'))).toEqual([])
  expect((await ui.find({ type: 'Text', text: /refused: number/ }))?.text).toBeDefined()
  await ui.unmount()
})
