# Status: Long-running test orchestration

**Change:** long-running-test-orchestration
**Started:** 2026-07-24
**Last Updated:** 2026-07-24

## Progress

| Phase | Status | Notes |
|-------|--------|-------|
| Proposal | ✅ Approved | Approved 2026-07-24; Q2/Q3/Q4/Q6 resolved at approval |
| Spec | ✅ Done | 14 FR, 7 NFR, 16 AC, 17 edge cases |
| Design | ✅ Done | 4 seams, 10 key decisions, grounding sources cited |
| Tasks | ✅ Done | 12 tasks in 5 waves (4 root causes + release) |
| Build | ✅ Done | All 5 waves committed 2026-07-24/25; T1–T12 |
| Verify | ⚠️ Partial |  |

## Task Progress

**Completed:** 12 / 12
**Failed:** 0

## Test Status

`run-long-orchestration-tests.sh` — **261 passed, 0 failed** (registered in the CI `test` job by T12).
`run-memory-parallelism-tests.sh` — 16 passed, 0 failed.
`run-parser-tests.sh` — 30 passed, 11 failed **locally only**: `jq` is not installed on this
machine and 11 cases shell out to it (`jq: command not found`). Identical failures reproduce at
`origin/main`, so this is an environment gap, not a regression. CI installs `jq` first.
`shellcheck` is likewise unavailable locally, so T12's "no new findings" check runs in CI only.

## Agent Runs

| Task | Agent | Model | Status | Duration |
|------|-------|-------|--------|----------|

## Issues

- ℹ️ Evidence in `proposal.md` / `spec.md` / `design.md` was sanitized before the GitHub Issue was filed (2026-07-25): the consumer project, its repo/channel names, PR numbers, spec filenames and verbatim operator quotes were generalized. `specclaw-gh-sync` rebuilds the issue body from `proposal.md` on every `update`, and `.specclaw/changes/` is git-tracked in a public repo, so the source files — not just the issue — had to be scrubbed. Failure modes, counts and durations are preserved.
**GitHub Issue:** #47
