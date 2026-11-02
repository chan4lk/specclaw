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
      on('command.register', () => ({ value: { command: 'specclaw-pane' } }))
      on('ui.open', () => ({ value: { isPlaced: true } }))
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

test('FR8 a tool that fails after the gate allowed it runs once', async ($, on) => {
  let runs = 0
  on('session.cwd', () => ({ value: '/x' }))
  on('fs.exists', () => ({ value: false }))
  on('tool.call', () => {
    runs += 1
    throw new Error('the tool fails')
  })
  await $.tool.call({ tool: 'Write', file_path: '/x/a.ts', content: 'a' }).catch(() => undefined)
  expect(runs).toBe(1)
})
