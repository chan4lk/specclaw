# Tasks: quality scan survives large repos (jq argument limit)

**Change:** 068-quality-scan-jq-arg-limit
**Created:** 2026-11-19
**Total Tasks:** 1

## Summary

Pass the scan's tables to `jq` by file and prove it with an oversized function table (T1).

## Tasks

### Wave 1 — tables by file

- [ ] `T1` — Tables reach `jq` by `--slurpfile`; oversized-table test (AC-1, AC-2)
  - Files: plugins/specclaw/bin/specclaw-quality-scan, plugins/specclaw/tests/run-quality-scan-tests.sh
  - Estimate: small
  - Kind: backend
  - Notes: FR-1, FR-2. The new case uses a second fake lizard that prints enough CSV rows to exceed
    `getconf ARG_MAX`; keep every existing case green.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
