import { parseChange, type Change, type Snapshot } from '../hooks/core/state.ts'

const state = (phase: string, extra = '') =>
  `{"phase":"${phase}","phases":{"proposal":{"status":"approved"}${extra}}}`

export const FULL = parseChange({
  name: '046-full',
  state: state('pr', ',"verify":{"verdict":"PASS"},"pr":{"url":"https://x/pr/1"}'),
  tasks: '- [x] `T1` — a\n- [!] `T2` — b\n- [ ] `T3` — c\n- [ ] not a task',
  mtimeMs: 10,
})

export const LEAN = parseChange({
  name: '047-lean',
  state: state('build'),
  lean: '## Problem\n- [x] `T9` — no\n## Tasks\n- [x] `T1` — a\n- [~] `T2` — b\n## Verify\n',
  mtimeMs: 20,
})

export const snapshot = (...changes: Change[]): Snapshot => ({ hasSpecclaw: true, changes })

export const NONE: Snapshot = { hasSpecclaw: false, changes: [] }
