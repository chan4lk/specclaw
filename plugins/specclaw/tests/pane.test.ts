import { expect, test } from 'claude-code/testing'

const OPEN: [string, () => unknown, string, boolean][] = [
  ['opens', () => ({ value: { isPlaced: true } }), 'specclaw pane opened.', false],
  ['rejects', () => ({ deny: 'no room' }), 'specclaw pane could not be opened.', true],
  ['throws', () => { throw new Error('ui.open throws') }, 'specclaw pane could not be opened.', true],
]

for (const [why, open, text, toasted] of OPEN) {
  test(`FR4 /specclaw-pane when ui.open ${why}`, async ($, on) => {
    const toasts: string[] = []
    on('ui.toast', (_, e) => (toasts.push(JSON.stringify(e)), { value: undefined }))
    on('ui.status', () => ({ value: undefined }))
    on('session.cwd', () => ({ value: '/x' }))
    on('fs.exists', () => ({ value: false }))
    on('ui.open', open)
    const ran = await $.command.run({ command: 'specclaw-pane', args: '' })
    expect([(ran as { text: string }).text, toasts.some(t => t.includes('pane could not be opened'))]).toEqual([text, toasted])
  })
}
