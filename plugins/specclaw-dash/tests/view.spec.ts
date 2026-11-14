import { expect, test } from 'bun:test'
import type { DashView, TokenData } from '../types/index.d.ts'
import { bandText, paneLines, statusText } from '../hooks/core/view.ts'
import { NOW } from './fixtures.ts'

const TOKENS: TokenData = {
  today: { tokens: 1_234_000, usd: 3.2 }, week: { tokens: 9_100_000, usd: 22.1 },
  sessions: [{ name: 'Build 062', tokens: 9_000_000, usd: 20, context: 340_000 }],
  roles: [{ name: 'main', tokens: 1, usd: 18 }, { name: 'code-reviewer', tokens: 1, usd: 4.1 }].map(r => ({ ...r, context: null })),
  files: 12, skipped: 0, unreadable: 0,
}

export const VIEW: DashView = {
  at: NOW,
  build: { kind: 'ok', data: {
    changes: [
      { name: '062-dash-pane', phase: 'build', done: 1, total: 4, failed: 0, verdict: null, pr: null, span: { label: 'wave 1', since: NOW - 12 * 60000 } },
      { name: '059-core', phase: 'verify', done: 4, total: 4, failed: 1, verdict: 'PASS', pr: 'https://github.com/x/pull/129', span: null },
    ],
    fleet: { kind: 'ok', data: { running: 2, prs_open: 1, jobs: 3, generated_at: new Date(NOW - 120000).toISOString() } },
  } },
  review: { kind: 'ok', data: [{ name: '059-core', rounds: 17, status: 'clean', blocker: 0, major: 0, minor: 4, escalated: 0, finalHead: '03a8e23b4610feab', atHead: true }] },
  learning: { kind: 'ok', data: {
    lessons: [{ change: '059-core', category: 'pattern', priority: 'high', detail: 'say hi', at: '' }],
    byCategory: { pattern: 1 }, proposed: { kind: 'ok', data: 3 },
  } },
  tokens: { kind: 'ok', data: TOKENS },
}

test('R062 AC-6 band and status line', () => {
  expect(bandText(VIEW)).toBe('dash · 1 building · 1 in review · $3.20 today, API-equivalent estimate')
  expect(statusText(VIEW)).toBe('dash: 1 building · $3.20 today (API-equivalent estimate)')
})

test('R062 AC-4 AC-6 the pane draws every part; every cost sits under the labelled tokens header', () => {
  const lines = paneLines(VIEW, NOW)
  expect(lines).toContain('  062-dash-pane                build    1/4      wave 1 12m')
  expect(lines).toContain('  059-core                     verify   4/4 ✗1   PASS PR 129')
  expect(lines).toContain('  fleet · 2 running · 1 PRs open · 3 jobs · snapshot 2m old')
  expect(lines).toContain('  059-core                     17 rounds · clean · last 0/0/4 b/M/m · 0 escalated · final 03a8e23b46 at HEAD')
  expect(lines).toContain('  1 lessons · pattern 1')
  expect(lines).toContain('  3 proposed rules awaiting approval (specclaw-review learn)')
  expect(lines).toContain('  today 1.2M tokens · $3.20 · 7 days 9.1M tokens · $22.10')
  expect(lines).toContain('  Build 062                       $20.00 · context 34%')
  const header = lines.findIndex(l => l.startsWith('TOKENS'))
  expect(lines[header]).toContain('API-equivalent estimate')
  expect(lines.findIndex(l => l.includes('$'))).toBeGreaterThan(header)
})

test('R062 AC-5 a skipped big transcript makes every total a lower bound', () => {
  const view = { ...VIEW, tokens: { kind: 'ok' as const, data: { ...TOKENS, skipped: 2 } } }
  const lines = paneLines(view, NOW)
  expect(lines).toContain('  today ≥1.2M tokens · ≥$3.20 · 7 days ≥9.1M tokens · ≥$22.10')
  expect(lines).toContain('  12 transcripts · 2 over 4 MiB not counted (totals are a lower bound)')
  expect(bandText(view)).toContain('≥$3.20 today')
})

test('R062 AC-5 missing sources show their card; errors show one line and no numbers', () => {
  const view: DashView = {
    at: NOW,
    build: { kind: 'ok', data: { changes: [], fleet: { kind: 'missing', card: 'fleet: no report. Install specclaw-fleet' } } },
    review: { kind: 'missing', card: 'Review loop: install specclaw-review' },
    learning: { kind: 'ok', data: { lessons: [], byCategory: {}, proposed: { kind: 'error', error: 'learn_propose failed' } } },
    tokens: { kind: 'error', error: 'could not list transcripts' },
  }
  const lines = paneLines(view, NOW)
  expect(lines).toContain('  fleet: no report. Install specclaw-fleet')
  expect(lines).toContain('  Review loop: install specclaw-review')
  expect(lines).toContain('  error: learn_propose failed')
  expect(lines).toContain('  error: could not list transcripts')
  expect(lines.some(l => l.includes('$'))).toBe(false)
  expect([bandText(view), statusText(view)]).toEqual(['dash · 0 building · 0 in review', 'dash: 0 building'])
})

test('R062 AC-5 no .specclaw: install card, no band; unreadable changes: an error band', () => {
  const none: DashView = { ...VIEW, build: { kind: 'missing', card: 'No .specclaw/ here. Install specclaw' } }
  expect(paneLines(none, NOW)).toContain('  No .specclaw/ here. Install specclaw')
  expect([bandText(none), statusText(none)]).toEqual([undefined, undefined])
  const bad: DashView = { ...VIEW, build: { kind: 'error', error: 'x' } }
  expect([bandText(bad), statusText(bad)]).toEqual(['dash · could not read changes', 'dash: could not read changes'])
})
