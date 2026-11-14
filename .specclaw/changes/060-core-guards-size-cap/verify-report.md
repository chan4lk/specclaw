# Verify Report: 060-core-guards-size-cap

**Verdict:** FAIL
**Head:** 1bf0664
**Date:** 2026-11-14

## Acceptance Criteria

- AC-1: pass. gate.spec.ts (bun, 17/17 across the spec files).
- AC-2: pass. branch.test.ts via `claude plugin test` (76/76 kit tests); live session not checked for the branch guard.
- AC-3: pass. run-done-guard-tests.sh 21/21; live `claude -p` run showed done-guard exit 2 then exit 0 on stop_hook_active.
- AC-4: pass. run-size-cap-tests.sh 20/20.
- AC-5: pass. run-codex-plugin-tests.sh 54/54; run-mod-tests.sh passes (validate, plugin test).
- AC-6: pass. Docs updated; both suites registered in ci.yml.

## Test Results

All specclaw suites pass except four that fail identically on origin/main on this macOS host
(change-numbering 6, long-orchestration 3, phase-state 1, synth-agent 1). shellcheck gate: no new findings.

## Review

Review: ESCALATE — 10 rounds, final pass missing, models sonnet/opus; last round 0/3/4 b/M/m

The local review loop escalated twice (rounds 8 and 10, final pass, Opus) on the done guard's
fail-open handling (fingerprint d88c3b169f28): each round finds another path where an internal
failure is skipped silently. Per the review skill, patching stopped and the question goes to the
operator. Round 10's open majors: an unparseable tasks file is skipped silently; uncommitted code
edits after verify are not compared with the verdict; test exclusions are case-sensitive and miss
spec/, *Tests.*, *Test.* layouts.

## Size

size cap: 327 production lines against origin/main @ 06a78e88a6 (cap 400); over half the cap, consider splitting.
