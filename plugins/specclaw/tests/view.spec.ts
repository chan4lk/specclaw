import { expect, test } from 'bun:test'
import { bandText, paneLines, statusText } from '../hooks/core/view.ts'
import { FULL, LEAN, NONE, snapshot } from './fixtures.ts'

test('AC4 pane rows, band text and both empty states', () => {
  expect(paneLines(snapshot(FULL))).toEqual(['046-full  pr  1/3  ✗1  PASS  https://x/pr/1'])
  expect(paneLines(snapshot())).toEqual(['No active specclaw changes.'])
  expect(paneLines(NONE)).toEqual(['No .specclaw/ in this project.'])
  expect(paneLines({ ...snapshot(), isUnreadable: true })).toEqual(['Could not read .specclaw/changes.'])
  expect(bandText(snapshot(FULL, LEAN))).toBe('specclaw · 047-lean · build · 1/2 tasks')
  expect(bandText(snapshot())).toBeUndefined()
})

test('AC5 status text with and without a build in progress', () => {
  expect(statusText(snapshot(FULL, LEAN))).toBe('specclaw: 2 active · building 047')
  expect(statusText(snapshot(FULL))).toBe('specclaw: 1 active')
  expect(statusText(NONE)).toBeUndefined()
  expect(statusText({ ...snapshot(), isUnreadable: true })).toBe('specclaw: could not read changes')
})
