import { expect, test } from 'bun:test'
import { readFileSync } from 'node:fs'
import { baseBranchFrom } from '../hooks/core/base.ts'

// The same table drives lib/base-ref.sh's base_config_branch in run-size-cap-tests.sh.
const rows = readFileSync(new URL('./fixtures/base-branch.tsv', import.meta.url), 'utf8').trim().split('\n')

for (const row of rows) {
  const [name, config, want] = row.split('|')
  test(`base_branch parity: ${name}`, () => {
    expect(baseBranchFrom((config ?? '').replaceAll('\\n', '\n'))).toBe(want === '-' ? '' : want ?? '')
  })
}
