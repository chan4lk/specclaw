# Verify Report: 060-core-guards-size-cap

**Verdict:** FAIL
**Head:** d38ec3d
**Date:** 2026-11-14

## Acceptance Criteria

- AC-1: pass. gate.spec.ts (bun, 17/17 across the spec files).
- AC-2: pass. branch.test.ts via `claude plugin test` (76/76 kit tests); live session not checked for the branch guard.
- AC-3: pass. run-done-guard-tests.sh 29/29; live `claude -p` run showed done-guard exit 2 then exit 0 on stop_hook_active.
- AC-4: pass. run-size-cap-tests.sh 64/64 (bash 3.2 row exercised); base.spec.ts 10/10 parity rows.
- AC-5: pass. run-codex-plugin-tests.sh 54/54; run-mod-tests.sh passes (validate, plugin test).
- AC-6: pass. Docs updated; both suites registered in ci.yml.

## Test Results

All specclaw suites pass except four that fail identically on origin/main on this macOS host
(change-numbering 6, long-orchestration 3, phase-state 1, synth-agent 1). shellcheck gate: no new findings.

## Review

Review: ESCALATE — 15 rounds, final pass missing, models sonnet/opus; last round 0/3/2 b/M/m

After the operator's decision (one skip() path, dirty tree goes stale, case-insensitive test layouts),
rounds 11-12 were clean, and the final pass escalated twice more on new fingerprints in recurring classes:
round 14 (310dbcb5f446 one base_branch reader; 61ccb8b6ac24 test layouts) and round 15
(b9024b2769a8 done guard silent when .specclaw/ is below the git toplevel; de966eb7f8b9 more test layouts:
tests.py, conftest.py, *_tests.*, e2e/, cypress/; plus 3bb88cbd75e1 CRLF parity). The loop is not
converging, so it stopped here for an operator decision instead of looping.

## Size

size cap: 389 production lines against origin/main @ 06a78e88a6 (cap 400); over half the cap, consider splitting.
