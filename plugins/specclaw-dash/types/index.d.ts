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
  approved: boolean
  feature: string | null
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

// One rule specclaw-review's learn_propose proposes, by its fingerprint.
export type RuleRow = { fp: string; seen: number; lesson: string }

export type LearningData = { lessons: LessonRow[]; byCategory: Record<string, number>; proposed: Section<RuleRow[]> }

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

// A role's context cap as `specclaw-budget roles --json` prints it (change 065).
export type CapRow = { role: string; context: number; default: number; min: number; max: number; source: string }

// The launch selection, the dry run of exactly it, the last command (code null: put into the prompt), the lists.
export type Ran = { command: string; code: number | null; out: string }
export type Actions = {
  selected: string[]
  plan: { items: string[]; launchable: string[] } | null
  last: Ran | null
  caps: Section<CapRow[]> | null
  dismissed: Section<string[]> | null
}

declare module 'claude-code' {
  interface PluginState {
    'specclaw-dash': { view: Shaped<DashView>; actions: Shaped<Actions> }
  }
}
