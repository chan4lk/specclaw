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

- [~] `T2` — Replace NR == FNR with FILENAME == ARGV[1] in run_jscpd join (AC-1, AC-2)
  - Files: plugins/specclaw/lib/quality-scan.sh
  - Estimate: small
  - Kind: impl
  - Depends: T1
  - Notes: line ~993 only; leave line 437 alone.
