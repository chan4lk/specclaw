import { expect, test } from 'bun:test'
import { readFileSync } from 'node:fs'
import { parseReport } from '../hooks/core/report.ts'
import { bandText, paneLines } from '../hooks/core/view.ts'
import { DONE, NOW, OPEN, doc } from './fixtures.ts'

const ROOT = `${import.meta.dir}/..`
type Node = { textContent: string; className?: string; style: Record<string, string>; children: Node[]; appendChild: (n: Node) => Node }
const node = (): Node => {
  const n: Node = { textContent: '', style: {}, children: [], appendChild: c => (n.children.push(c), c) }
  return n
}

const htmlTiles = (json: string) => {
  const html = readFileSync(`${ROOT}/lib/report.html`, 'utf8')
  const script = html.slice(html.lastIndexOf('<script>') + 8, html.lastIndexOf('</script>'))
  const ids: Record<string, Node> = { data: { ...node(), textContent: json } }
  const document = { getElementById: (id: string) => (ids[id] ??= node()), createElement: () => node() }
  new Function('document', script)(document)
  return Object.fromEntries(ids.totals.children.map(t => [t.textContent, t.children[0]?.textContent]))
}

const shellTable = (json: string) =>
  Bun.spawnSync(['bash', '-c', `source "${ROOT}/lib/report-render.sh"; jq -r "$REPORT_TABLE"`], { stdin: Buffer.from(json) }).stdout.toString()

const CASES: [string, string[], boolean, boolean][] = [
  ['hosted only', ['hosted_s'], true, false],
  ['PRs only', ['prs_open'], false, true],
  ['both', ['hosted_s', 'prs_open'], true, true],
  ['neither', [], false, false],
]

for (const [name, partial, hosted, prs] of CASES) {
  test(`R054 AC-4 every renderer marks a partial total with ≥: ${name}`, () => {
    const json = doc([OPEN, DONE], { prs_open: 1, partial })
    const view = parseReport(json)
    const h = hosted ? '≥' : '', p = prs ? '≥' : ''
    expect(bandText(view, NOW)).toContain(`· ${p}1 PRs open`)
    const pane = paneLines(view, NOW).join('\n')
    expect(pane).toContain(`hosted ${h}2m`)
    expect(pane).toContain(`· ${p}1 PRs open`)
    const table = shellTable(json)
    expect(table).toContain(`hosted ${h}2m`)
    expect(table).toContain(`· ${p}1 PRs open`)
    const tiles = htmlTiles(json)
    expect([tiles['Hosted pipeline'], tiles['PRs open']]).toEqual([`${h}2m`, `${p}1`])
  })
}
