import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'
import { parseReport, type View } from './core/report.ts'
import { statusText } from './core/view.ts'

const NONE: View = { kind: 'none' }
const UNREADABLE: View = { kind: 'unreadable' }
const report = atom({ plugin: 'specclaw-fleet', key: 'report' } as const, NONE, { shape: 'fleet-report-1' })

async function readReport($: EngineInterface): Promise<View> {
  const path = `${await $.session.cwd()}/.specclaw/fleet/report.json`
  if (!(await $.fs.exists(path))) return NONE
  const text = await $.fs.read(path)
  return typeof text === 'string' ? parseReport(text) : UNREADABLE
}

async function show($: EngineInterface, view: View) {
  await update($, report, () => view)
  await Promise.resolve().then(() => $.ui.status(statusText(view))).catch(() => undefined)
}

export async function refreshQuietly($: EngineInterface) {
  await readReport($).then(view => show($, view), () => show($, UNREADABLE).catch(() => undefined))
}

export async function notify($: EngineInterface, text: string) {
  await Promise.resolve().then(() => $.ui.toast(text)).catch(() => undefined)
}

export async function readView($: EngineInterface) {
  return read($, report)
}
