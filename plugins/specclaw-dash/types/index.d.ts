// Every section is ok with its data, missing with an install card, or error with one line: a failed read
// never keeps numbers, so it is never drawn as live data.
export type Section<T> = { kind: 'ok'; data: T } | { kind: 'missing'; card: string } | { kind: 'error'; error: string }

export type ChangeRow = {
  name: string
  phase: string
  done: number
  total: number
  failed: number
  verdict: string | null
  pr: string | null
  span: { label: string; since: number } | null
}

export type FleetLine = { running: number; prs_open: number; jobs: number; generated_at: string }

export type BuildData = { changes: ChangeRow[]; fleet: Section<FleetLine> }

export type ReviewRow = {
  name: string
  rounds: number
  status: string
  blocker: number
  major: number
  minor: number
  escalated: number
  finalHead: string | null
  atHead: boolean | null
}

export type LessonRow = { change: string; category: string; priority: string; detail: string; at: string }

export type LearningData = { lessons: LessonRow[]; byCategory: Record<string, number>; proposed: Section<number> }

export type Spend = { tokens: number; usd: number }
export type TokenRow = Spend & { name: string; context: number | null }

export type TokenData = {
  today: Spend
  week: Spend
  sessions: TokenRow[]
  roles: TokenRow[]
  files: number
  skipped: number
  unreadable: number
}

export type DashView = {
  at: number
  build: Section<BuildData>
  review: Section<ReviewRow[]>
  learning: Section<LearningData>
  tokens: Section<TokenData>
}

declare module 'claude-code' {
  interface PluginState {
    'specclaw-dash': { view: Shaped<DashView> }
  }
}
