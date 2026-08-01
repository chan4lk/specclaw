# Tasks: Tracker state integrity

**Change:** tracker-state-integrity
**Created:** 2026-08-01
**Total Tasks:** 7

## Summary

Seven tasks in three waves. Wave 1 builds the writer and its tests. Wave 2 routes every existing
call site through it — three independent files, parallelisable. Wave 3 adds the drift detector and
wires CI.

**Prerequisite:** this change depends on `bin/specclaw-status-row` from PR #52. Branch from
`claude/fix-status-row-sed` or wait for it to merge before starting Wave 1.

## Tasks

### Wave 1 — The writer

- [ ] `T1` — Create `specclaw-set-phase`, the sole phase writer
  - Files: `plugins/specclaw/bin/specclaw-set-phase`
  - Estimate: large
  - Kind: impl
  - Notes: Implements FR1–FR3. Args per spec FR2. Atomic write (mktemp → validate parses → mv).
    Phase rank list `proposal spec design tasks build verify pr archived`; reject a lower rank than
    the recorded `phase` unless `--force`, allow equal rank. Delegate the human row to
    `specclaw-status-row`, self-healing `status.md` from `templates/status.md` when absent
    (mirror `specclaw-verify:541-557`). Unknown phase name → usage error listing valid phases.
    Reads via a `state_field` helper: `jq` when present, `python3 -c` fallback, empty on any error.

- [ ] `T2` — Regression suite for `specclaw-set-phase`
  - Files: `plugins/specclaw/tests/run-phase-state-tests.sh`
  - Estimate: medium
  - Kind: test
  - Depends: T1
  - Notes: Covers AC1–AC4 plus edge cases 4, 5, 6, 8, 9, 10. Mirror the harness style of
    `tests/run-status-row-tests.sh` — plain bash + coreutils, `pass`/`fail` counters, `mktemp -d`
    workdir, non-zero exit on failure. AC2 asserts with `cmp`. AC4 asserts the `GitHub Issue` line
    is untouched after a PR transition. Include a `| url | with | pipes |` case (edge 9).

### Wave 2 — Route every call site through it

- [ ] `T3` — Wire the lifecycle to `set-phase`
  - Files: `plugins/specclaw/bin/specclaw-build`, `plugins/specclaw/bin/specclaw-verify`, `plugins/specclaw/skills/propose/SKILL.md`, `plugins/specclaw/skills/plan/SKILL.md`, `plugins/specclaw/skills/archive/SKILL.md`
  - Estimate: large
  - Kind: refactor
  - Depends: T1
  - Notes: FR4, FR5. Build records the real branch name (not `${branch_prefix}${change}`) plus task
    counts on completion. Verify replaces its hand-rolled row rewrite at `specclaw-verify:570-610`
    with a `set-phase … verify <status> --verdict` call; delete the dead code rather than leaving
    both paths. The three SKILL.md files call `specclaw-set-phase` at their transition instead of
    instructing the model to edit `status.md` prose — that instruction is why the Build row drifts
    (`skills/build/SKILL.md:100`).

- [ ] `T4` — Route `save_pr_url` in both PR scripts through `set-phase`, fail-soft
  - Files: `plugins/specclaw/bin/specclaw-pr`, `plugins/specclaw/bin/specclaw-azdo-pr`
  - Estimate: medium
  - Kind: refactor
  - Depends: T1
  - Notes: FR9 / AC11. Everything after `gh pr create` is bookkeeping: guard it so a failure warns
    loudly and continues, never aborts under `set -euo pipefail`. Keep the `specclaw-status-row`
    call path from PR #52 intact underneath — this only moves the *decision* into `set-phase`.

- [ ] `T5` — `specclaw-update-status` reads `state.json`
  - Files: `plugins/specclaw/bin/specclaw-update-status`
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: FR6 / FR7, AC5–AC7. Render the recorded phase; use the recorded `branch` for
    `pr_state_for` instead of `${BRANCH_PREFIX}${change}`. Absent, unreadable, or malformed state
    must fall through to the existing checkbox inference with a stderr warning and exit 0 — AC6
    requires byte-identical output to today for a change with no `state.json`. Skip nothing under
    `archive/` (edge 7).

### Wave 3 — Drift detection and CI

- [ ] `T6` — Create `specclaw-reconcile` and cover it
  - Files: `plugins/specclaw/bin/specclaw-reconcile`, `plugins/specclaw/tests/run-phase-state-tests.sh`
  - Estimate: large
  - Kind: impl
  - Depends: T2, T5
  - Notes: FR8, AC9–AC10. Compare `state.json` against `tasks.md` markers, `verify-report.md`
    presence, and `gh pr view` on the *recorded* branch. Report exits non-zero on drift; `--fix`
    adopts reality. A `gh` failure is `unknown` — never `no PR` — and `--fix` skips unknowns and
    says so. Extend the T2 suite rather than adding a second file.

- [ ] `T7` — Register the suite in CI and document the writer
  - Files: `.github/workflows/ci.yml`, `plugins/specclaw/tests/shellcheck-baseline.txt`, `plugins/specclaw/CLAUDE.md`, `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Kind: config
  - Depends: T6
  - Notes: NFR3 / AC12. Add a named step for `run-phase-state-tests.sh` under the parser job.
    `bash plugins/specclaw/tests/shellcheck-gate.sh` must pass with no new findings — touch the
    baseline only if pre-existing findings shift line numbers. Document `specclaw-set-phase` as the
    only phase writer in `plugins/specclaw/CLAUDE.md`. Bump both version files in lockstep (the CI
    `json` job asserts they match).

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
