import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import type { Snapshot } from './core/state.ts'
import { statusText } from './core/view.ts'
import { readSnapshot } from './read.ts'

const EMPTY: Snapshot = { hasSpecclaw: false, changes: [] }
const UNREADABLE: Snapshot = { hasSpecclaw: true, isUnreadable: true, changes: [] }
const snapshot = atom({ plugin: 'specclaw', key: 'snapshot' } as const, EMPTY, { shape: 'snapshot-2' })

export async function refresh($: EngineInterface) {
  const latest = await readSnapshot($, await $.session.cwd())
  await update($, snapshot, () => latest)
  $.ui.status(statusText(latest))
  return latest
}

export async function notify($: EngineInterface, text: string) {
  await Promise.resolve().then(() => $.ui.toast(text)).catch(() => Promise.resolve().then(() => $.ui.status(text)).catch(() => undefined))
}

export async function refreshQuietly($: EngineInterface) {
  await refresh($).catch(async () => {
    await Promise.resolve().then(() => $.ui.status(statusText(UNREADABLE))).catch(() => undefined)
    await update($, snapshot, () => UNREADABLE).catch(() => undefined)
  })
}

export async function readView($: EngineInterface) {
  return read($, snapshot)
}
