import { expect, test } from 'bun:test'
import { parseReport } from '../hooks/core/report.ts'
import { bandText, paneLines, statusText, timeline } from '../hooks/core/view.ts'
import { DONE, LIVE, NOW, OPEN, doc } from './fixtures.ts'

const CASES: [string, string | undefined, string | undefined, string | undefined, string][] = [
  ['no snapshot', undefined, undefined, undefined, 'No fleet report yet.'],
  ['not JSON', '{nope', 'fleet · report unreadable', 'fleet: report unreadable', 'fleet · report unreadable'],
  ['wrong version', JSON.stringify({ version: 2, generated_at: 'x', rows: [], totals: {} }), 'fleet · report unreadable', 'fleet: report unreadable', 'fleet · report unreadable'],
  ['generated_at not a date', JSON.stringify({ version: 1, generated_at: 'soon', rows: [], totals: {} }), 'fleet · report unreadable', 'fleet: report unreadable', 'fleet · report unreadable'],
  ['rows not a list', JSON.stringify({ version: 1, generated_at: 'x', rows: {}, totals: {} }), 'fleet · report unreadable', 'fleet: report unreadable', 'fleet · report unreadable'],
  ['one running row', doc([LIVE]), 'fleet · 1 running · 0 PRs open · last run 11:53 UTC', 'fleet: 1 running', 'fleet build · latest · snapshot 2m old'],
  ['mixed rows', doc([OPEN, DONE, LIVE], { prs_open: 1 }), 'fleet · 1 running · 1 PRs open · last run 11:53 UTC', 'fleet: 1 running', 'fleet build · latest · snapshot 2m old'],
  ['empty build', doc([]), 'fleet · 0 running · 0 PRs open', 'fleet: 0 running', 'fleet build · latest · snapshot 2m old'],
]

for (const [name, text, band, status, head] of CASES) {
  test(`R054 AC-4 band, status and pane header: ${name}`, () => {
    const view = parseReport(text)
    expect([bandText(view, NOW), statusText(view, NOW), paneLines(view, NOW)[0]]).toEqual([band, status, head])
  })
}

test('R054 AC-4 a snapshot older than an hour says so on the band and status line', () => {
  const view = parseReport(doc([LIVE]))
  const later = NOW + 3 * 3600 * 1000
  expect([bandText(view, later), statusText(view, later)]).toEqual(['fleet · 1 running · 0 PRs open · last run 11:53 UTC · snapshot 3h old', 'fleet: 1 running · snapshot 3h old'])
})

test('R054 AC-4 junk fields are dropped, not trusted', () => {
  const view = parseReport(doc([{ ...DONE, agent_s: '1800', pr: 7 }, { nochange: true }, 'x']))
  expect(view.kind === 'report' && view.report.rows.map(r => [r.change, r.agent_s, r.pr])).toEqual([['002-catalog', null, null]])
})

test('R054 AC-4 timeline scales every row to one window and marks pipeline, agent and open PR', () => {
  const [done, live, open] = timeline([DONE, LIVE, OPEN], NOW, 12)
  expect([done, live, open]).toEqual(['░███████▒▒▒·', '··········██', '░███████▒▒▒▒'])
})

test('R054 AC-4 pane lists the timeline, the lifecycle table in wave order, totals and the refresh command', () => {
  const view = parseReport(doc([LIVE, DONE], { prs_open: 0 }))
  const lines = paneLines(view, NOW, 40)
  expect(lines.slice(1, 3)).toEqual(['wall 1h 0m · 2 jobs · agent 30m · hosted 2m · 3 rounds · 7 commits', '1 running · 0 PRs open · cost $2.50 (API-equivalent estimate)'])
  const rows = lines.filter(l => /^00\d-/.test(l)).map(l => l.split(/\s+/).slice(0, 3).join(' '))
  expect(rows.map(l => l.replace(/[░█▒·]{10,}/, 'BAR'))).toEqual(['002-catalog BAR', '003-detail BAR', '002-catalog 1 pr_open', '003-detail 2 running'])
  expect(lines.at(-1)).toBe('Refresh: specclaw-fleet report --save')
})
