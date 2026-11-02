import { expect, test } from 'claude-code/testing'

const FAILURES: [string, () => unknown][] = [
  ['throws', () => {
    throw new Error('refresh throws')
  }],
  ['rejects', async () => {
    throw new Error('refresh rejects')
  }],
]

for (const [shape, fail] of FAILURES) {
  test(`FR6 a refresh that ${shape} after a tool call runs the tool once and keeps its result`, async ($, on) => {
    let runs = 0
    on('tool.call', () => {
      runs += 1
      return { result: { stdout: 'ok' } }
    })
    on('session.cwd', fail)
    const ran = await $.tool.call({ tool: 'Bash', command: 'cat .specclaw/x' })
    expect(runs).toBe(1)
    expect(ran.result).toEqual({ stdout: 'ok' })
  })
}
