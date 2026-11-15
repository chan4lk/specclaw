# Verify Report: 064-sync-clean-status-release-gate

**Verified:** 2026-11-14
**Verdict:** PASS

## Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| AC-1 | MET | `run-review-tests.sh` "064 AC-1": `--head` at the final-pass SHA exits 0 and prints the round file; another SHA, a records-only commit after the final pass, and an open final pass all exit 1 |
| AC-2 | MET | `plugins/specclaw/tests/run-review-status-tests.sh` (7/7, stubbed `gh`): one `statuses/<sha>` POST on a match; none on mismatch (full and 10-char SHA), records-only drift, open verdict, unreadable head, or no `specclaw-review` |
| AC-3 | MET | `plugins/specclaw-sync/tests/run-azdo-review-status-tests.sh` (6/6, stubbed `curl`): one PR status POST with `succeeded`, `specclaw/review-loop`, `iterationId` 2 on a match; nothing on mismatch |
| AC-4 | MET | "064 AC-4": `Data Loss` → `data-loss`, missing/unknown → `other`; follow-up lines carry `class:` |
| AC-5 | MET | "064 AC-5" (10 checks): fast-track round is final; non-gate findings exit 0 and land once in `debt.md`; security blocker exits 1; `block_on: [law]` defers it; unlabelled blocker stays blocking; unlabelled major is `class:unclassified`; multi-line message stays one line; ticked item that recurs is re-listed; misspelt gate exits 2; fast track off is unchanged |
| AC-6 | MET | `run-release-tests.sh` (17/17): range listing, ticked/base items excluded, BLOCK + exit 1 on security and `unclassified`, `block_on` forms and parity with specclaw-review (12 configs), subdirectory, archive move adds nothing, misspelt class exit 2, unreadable listed file exit 2, bad ref exit 2 |
| AC-7 | MET | "064 AC-7": both templates have the verdict step and a status step gated by `verdict --head`; both parse as YAML |
| AC-8 | MET | 3 new suites added to `.github/workflows/ci.yml`; all touched suites pass except 4 that fail identically on `origin/main` (below) |

## Test runs

- specclaw-review: `run-review-tests.sh` 66/66
- specclaw-sync: all 8 suites pass (release 17, azdo-review-status 6, azdo-pr-description 28, jira 38, azdo-issue ×4)
- specclaw: 28 suites; 24 pass. `run-change-numbering` (6), `run-long-orchestration` (3), `run-phase-state` (1)
  and `run-synth-agent` (1) fail with the same failures on an unmodified `origin/main` checkout (macOS `wc`
  padding and environment), so they are not caused by this change.

E2E: not configured; no e2e evidence.

## Review

Review: CLEAN (+ records-only commits) — 6 rounds, final pass bbda9dfe26, models sonnet/opus; last round 0/0/4 b/M/m

**Code Review:** CHANGES_REQUESTED on the first diff — 5 findings: 1 BLOCK, 2 WARN, 2 NOTE. All were fixed in
later commits (one-line list items, `block_on: []` parity, fp dedup over open items only, `--full-name` and
top-level cwd). The strict-head WARN is the operator's requirement, documented in `SKILL.md` and `verdict_at`.
