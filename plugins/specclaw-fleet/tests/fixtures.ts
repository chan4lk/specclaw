const base = {
  wave: null, state: 'pr_open', exit: '0', queued: null, dispatched: null, finished: null, phase: null,
  agent_started: null, agent_ended: null, agent_s: null, review_rounds: null, agent_commits: null,
  cost_usd: null, pr: null, pr_status: null, pr_opened: null, pr_closed: null,
}

export const DONE = {
  ...base, change: '002-catalog', wave: 1, queued: '2026-11-09T11:00:00Z', finished: '2026-11-09T11:02:00Z',
  dispatched: '2026-11-09T11:01:00Z', agent_started: '2026-11-09T11:05:00Z', agent_ended: '2026-11-09T11:35:00Z', agent_s: 1800,
  review_rounds: 3, cost_usd: 2.5, pr: 'https://x/pullrequest/11', pr_status: 'completed',
  pr_opened: '2026-11-09T11:35:00Z', pr_closed: '2026-11-09T11:50:00Z',
}

export const LIVE = {
  ...base, change: '003-detail', wave: 2, state: 'running', exit: null, dispatched: '2026-11-09T11:51:00Z',
  agent_started: '2026-11-09T11:53:00Z', phase: 'active',
}

export const OPEN = { ...DONE, change: '004-share', pr: 'https://x/pullrequest/12', pr_status: 'active', pr_closed: null, cost_usd: null }

export const NOW = Date.parse('2026-11-09T12:00:00Z')

export const doc = (rows: object[], totals: object = {}) =>
  JSON.stringify({
    version: 1, generated_at: '2026-11-09T11:58:00Z', scope: 'latest', rows,
    totals: { wall_s: 3600, jobs: rows.length, agent_s: 1800, hosted_s: 120, review_rounds: 3, commits: 7, cost_usd: 2.5, running: 0, prs_open: 0, ...totals },
  })
