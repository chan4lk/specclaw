# Tasks: Windows (Git Bash) test portability

**Change:** 071-windows-test-portability
**Created:** 2026-11-18
**Total Tasks:** 4

## Summary

Fix `specclaw-presets` output, then the test's path/symlink handling, then the review decode, then bump.

## Tasks

### Wave 1 — Fixes

- [x] `T1` — `specclaw-presets` prints `\n` and `/` paths on every OS (AC-2, AC-5)
  - Files: plugins/specclaw/bin/specclaw-presets
  - Estimate: small
  - Kind: impl
- [x] `T2` — Preset test: `cygpath -m` on `P` and `L`, symlink guard with SKIP, output-shape check (AC-1, AC-2, AC-3)
  - Files: plugins/specclaw/tests/run-preset-check-tests.sh
  - Estimate: small
  - Kind: test
  - Depends: T1
- [x] `T3` — UTF-8 decode in `specclaw-review` git helper(s) (AC-4)
  - Files: plugins/specclaw-review/lib/review_core.py
  - Estimate: small
  - Kind: impl

### Wave 2 — Release

- [x] `T4` — Bump plugin versions (AC-6)
  - Files: plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T1, T2, T3

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
