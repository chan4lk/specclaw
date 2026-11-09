export type FleetRow = {
  change: string
  wave: number | null
  state: string | null
  exit: string | null
  queued: string | null
  dispatched: string | null
  finished: string | null
  phase: string | null
  agent_started: string | null
  agent_ended: string | null
  agent_s: number | null
  review_rounds: number | null
  agent_commits: number | null
  cost_usd: number | null
  pr: string | null
  pr_status: string | null
  pr_opened: string | null
  pr_closed: string | null
  note: string | null
}

export type FleetTotals = {
  wall_s: number | null
  jobs: number
  agent_s: number
  hosted_s: number
  review_rounds: number
  commits: number
  cost_usd: number | null
  running: number
  prs_open: number
  unknown: number
  partial: string[]
}

export type FleetView =
  | { kind: 'none' }
  | { kind: 'unreadable' }
  | { kind: 'report'; report: { generated_at: string; scope: string; rows: FleetRow[]; totals: FleetTotals } }

declare module 'claude-code' {
  interface PluginState {
    'specclaw-fleet': { report: Shaped<FleetView> }
  }
}
