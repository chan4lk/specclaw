# Tasks: quality-scan zero-clone join fix

**Change:** 046-quality-scan-zero-clone
**Created:** 2026-10-29
**Total Tasks:** 2

## Summary

Add a failing zero-clone regression test, then fix the awk join.

## Tasks

### Wave 1 — Regression test

- [x] `T1` — Add zero-clone case to run-quality-scan-tests.sh (AC-1, AC-3)
  - Files: plugins/specclaw/tests/run-quality-scan-tests.sh
  - Estimate: small
  - Kind: test
  - Notes: second fake jscpd emitting `"duplicates":[]` with two scanned files; assert jscpd ran, duplicated_lines 0, gate pass, rc 0. Must fail before T2.

### Wave 2 — Fix

- [x] `T2` — Replace NR == FNR with FILENAME == ARGV[1] in run_jscpd join (AC-1, AC-2)
  - Files: plugins/specclaw/lib/quality-scan.sh
  - Estimate: small
  - Kind: impl
  - Depends: T1
  - Notes: line ~993 only; leave line 437 alone.

### Wave 3 — Gate green

- [x] `T3` — Refactor the four complexity_high functions in specclaw-review review_core.py so `specclaw-quality-scan . --gate` passes (AC-4)
  - Files: plugins/specclaw-review/lib/review_core.py
  - Estimate: medium
  - Kind: refactor
  - Notes: parse_block, run_round, verdict, discover — extract helpers only, no behaviour change; tests/run-review-tests.sh stays green.

### Wave 4 — Version sync (done in 7d7de8e)

- [x] `T4` — Sync .codex-plugin versions to 0.8.4 and extend review rule R1 to cover them (AC-5)
  - Files: plugins/*/.codex-plugin/plugin.json, .specclaw/review/rules/versions.md
  - Estimate: small
  - Kind: config
