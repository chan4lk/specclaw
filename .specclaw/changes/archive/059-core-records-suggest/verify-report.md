# Verify Report: 059-core-records-suggest

**Verdict:** PASS
**Head:** 03a8e23 (code); the review records are committed on top of it

## Acceptance criteria

- AC-1: pass. `run-suggest-tests.sh` "AC-1 missing plugin prints the exact tip".
- AC-2: pass. A plugin installed in the plugin cache or on PATH prints nothing.
- AC-3: pass.
  - A dismissed feature prints nothing.
  - `--dismiss` is idempotent and creates the block when it is absent.
  - It folds 7 block-list shapes (gaps, comments, quoted items, same-indent items, CRLF) into one inline list, and keeps the template's comment.
  - Every write-failure path (no config, read-only dir, unreadable file, read-only file, late rename failure) says so on stderr, exits 0 and leaves the config unchanged.
  - Writes are a rename onto the real file, through relative, absolute, chained, `../` and directory symlinks.
- AC-4: pass. An unknown feature, a missing config and `CODEX_THREAD_ID` each print nothing and exit 0.
- AC-5: pass.
  - `session-start` sources `lib/plugins.sh` and has no copy of `installed()`.
  - The hook names a missing plugin until its feature is dismissed, for inline and block lists. The check has a positive control.
  - `run-plugin-split-tests.sh` and `run-bootstrap-hook-tests.sh` pass.
- AC-6: pass.
  - Each learning adds one valid `{"kind":"lesson",…}` line. Control characters are blanked and every field is escaped.
  - `specclaw-timer report` prints no "unparseable" warning. The check fails without the timer fix.
- AC-7: pass.
  - verify (lean and full), status, propose and init name `specclaw-suggest`.
  - verify no longer skips the review loop silently.
  - The lean skills stay within the 300-word cap (`run-lean-flow-tests.sh`).

## Commands

- `bash plugins/specclaw/tests/run-suggest-tests.sh`: exit 0, 38 PASS.
- All 28 `plugins/specclaw/tests/run-*.sh` at HEAD: 24 exit 0, and `run-trigger-tests.sh` (opt-in) is among them, skipped. 4 fail with the same counts on origin/main, so they were already failing:
  - change-numbering: 156 passed, 6 failed
  - long-orchestration: 269 passed, 3 failed
  - phase-state: 192 passed, 1 failed
  - synth-agent: 9 passed, 1 failed
- All 60 suites across the six plugins (the version bump touches every plugin): 46 exit 0. Each of the 14 failures was run again side by side in a clean origin/main worktree and matches it exactly. The 10 not listed above:
  - bf-status: 152 passed, 4 failed
  - blueprint: 125 passed, 14 failed
  - prototype byte-identity: 1 passed, 15 failed
  - prototype gates: 25 passed, 4 failed
  - prototype readiness-scope: 16 passed, 6 failed
  - prototype stack-resolver: 41 passed, 1 failed
  - prototype status-machine: 25 passed, 4 failed
  - quality: 9 failed
  - replay-classification: 200 passed, 4 failed
  - party: 280 passed, 1 failed
- `bash plugins/specclaw/tests/shellcheck-gate.sh`: exit 0, no new findings.
- `specclaw-preset-check .`: exit 1. Every violation is in `plugins/specclaw-review/{lib,mcp}/*.py`, which this change does not touch, and origin/main gives the same result.
- `specclaw-quality-scan . --gate`: exit 0. Quality: 0 → 0 duplicated lines.
- Screenshots: none. The change has no UI (bash scripts and skill text).

**Code Review:** APPROVED_WITH_NOTES. 4 findings: 0 BLOCK, 2 WARN, 2 NOTE. Review rounds 1 and 2 fixed both WARNs.
**Local review:** Review: CLEAN — 17 rounds, final pass 03a8e23b46, models sonnet/opus; last round 0/0/4 b/M/m
