import { expect, test } from 'claude-code/testing'
import type { EngineInterface } from 'claude-code'

const SHAPES: [string, () => unknown][] = [
  ['throws', () => {
    throw new Error('cwd throws')
  }],
  ['rejects', async () => {
    throw new Error('cwd rejects')
  }],
]

const EVENTS: [string, ($: EngineInterface) => Promise<unknown>][] = [
  ['session.start', $ => $.session.start({ cwd: '/x', surface: 'terminal', isInteractive: true })],
  ['command.run', $ => $.command.run({ command: 'specclaw-pane', args: '' })],
  ['turn.complete', $ => $.turn.complete({ answer: 'a', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' })],
]

for (const [shape, fail] of SHAPES) {
  for (const [event, raise] of EVENTS) {
    test(`FR6 ${event} goes on when the refresh ${shape}`, async ($, on) => {
      let reached = 0
      const statuses: (string | undefined)[] = []
      on('ui.status', (_, e) => (statuses.push(e.text), { value: undefined }))
      on('command.register', event === 'session.start' ? fail : () => ({ value: { command: 'specclaw-pane' } }))
      on('ui.open', () => ({ value: { isPlaced: true } }))
      on('ui.toast', fail)
      on('session.cwd', fail)
      on('session.start', (_, e) => (reached += 1, { cwd: e.cwd }))
      on('turn.complete', (_, e) => (reached += 1, { text: e.answer }))
      const ran = await raise($)
      const isCommand = event === 'command.run'
      expect(isCommand ? (ran as { text: string }).text : reached).toEqual(isCommand ? 'specclaw pane opened.' : 1)
      expect(statuses.at(-1)).toBe('specclaw: could not read changes')
    })
  }
}

const APPROVED = '{"phase":"build","phases":{"proposal":{"status":"approved"}}}'
const GATE_ROWS: [string, Record<string, string>, string][] = [
  ['no .specclaw', {}, 'block'],
  ['an approved change', { '/x/.specclaw': '', '/x/.specclaw/changes': '', '/x/.specclaw/changes/001-a/state.json': APPROVED }, 'block'],
  ['warn mode', { '/x/.specclaw': '', '/x/.specclaw/changes': '' }, 'warn'],
]

for (const [why, files, gate] of GATE_ROWS) {
  test(`FR8 a tool that fails after the gate allowed it (${why}) runs once`, { options: { gate } }, async ($, on) => {
    let runs = 0
    on('session.cwd', () => ({ value: '/x' }))
    on('fs.stat', (_, e) => ({ value: { kind: 'file', size: 0, mtimeMs: 1, isLink: false, realPath: e.path } }))
    on('fs.exists', (_, e) => ({ value: e.path === '/x' || files[e.path] !== undefined }))
    on('fs.list', () => ({ value: files['/x/.specclaw/changes/001-a/state.json'] ? [{ name: '001-a', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }] : [] }))
    on('fs.read', (_, e) => ({ value: files[e.path] ?? '' }))
    on('tool.call', () => {
      runs += 1
      throw new Error('the tool fails')
    })
    await $.tool.call({ tool: 'Write', file_path: '/x/a.ts', content: 'a' }).catch(() => undefined)
    expect(runs).toBe(1)
  })
}
