import { expect, test } from 'claude-code/testing'

test('FR6 a failing refresh after a tool call runs the tool once and keeps its result', async ($, on) => {
  let runs = 0
  on('tool.call', () => {
    runs += 1
    return { result: { stdout: 'ok' } }
  })
  on('session.cwd', () => {
    throw new Error('refresh fails')
  })

  for (const command of ['cat .specclaw/x', 'ls .specclaw']) {
    const ran = await $.tool.call({ tool: 'Bash', command })
    expect(ran.deny).toBeUndefined()
  }
  expect(runs).toBe(2)
})
