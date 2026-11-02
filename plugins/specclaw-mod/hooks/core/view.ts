import type { Change, Snapshot } from './state.ts'

export const active = (changes: Change[]) =>
  changes.filter(change => change.phase !== 'archived')

export const current = (changes: Change[]) =>
  active(changes).reduce<Change | undefined>(
    (best, change) => (!best || change.mtimeMs > best.mtimeMs ? change : best),
    undefined,
  )

const row = (change: Change) =>
  [
    change.name,
    change.phase,
    `${change.done}/${change.total}`,
    change.failed > 0 ? `✗${change.failed}` : '',
    change.verdict ?? '',
    change.pr ?? '',
  ]
    .filter(Boolean)
    .join('  ')

export const paneLines = (snapshot: Snapshot) => {
  if (!snapshot.hasSpecclaw) return ['No .specclaw/ in this project.']
  if (snapshot.isUnreadable) return ['Could not read .specclaw/changes.']
  const changes = active(snapshot.changes)
  return changes.length === 0 ? ['No active specclaw changes.'] : changes.map(row)
}

export const bandText = (snapshot: Snapshot) => {
  const change = snapshot.hasSpecclaw ? current(snapshot.changes) : undefined
  return change
    ? `specclaw · ${change.name} · ${change.phase} · ${change.done}/${change.total} tasks`
    : undefined
}

export const statusText = (snapshot: Snapshot) => {
  if (!snapshot.hasSpecclaw) return undefined
  if (snapshot.isUnreadable) return 'specclaw: could not read changes'
  const changes = active(snapshot.changes)
  const building = changes.find(change => change.phase === 'build')
  const suffix = building ? ` · building ${building.name.slice(0, 3)}` : ''
  return `specclaw: ${changes.length} active${suffix}`
}
