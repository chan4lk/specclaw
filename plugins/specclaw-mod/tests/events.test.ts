import { expect, test } from 'claude-code/testing'

const failingCwd = () => {
  throw new Error('cwd fails')
}

test('FR6 session.start and /specclaw-pane go on when the refresh fails', async ($, on) => {
  let starts = 0
  on('command.register', () => ({ value: { command: 'specclaw-pane' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.cwd', failingCwd)
  on('session.start', (_, e) => {
    starts += 1
    return { cwd: e.cwd }
  })

  await $.session.start({ cwd: '/x', surface: 'terminal', isInteractive: true })
  expect(starts).toBe(1)
  const ran = await $.command.run({ command: 'specclaw-pane', args: '' })
  expect(ran.text).toBe('specclaw pane opened.')
})

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
