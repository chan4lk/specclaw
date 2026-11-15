# Verify Report: 060-core-guards-size-cap

**Verdict:** PASS WITH FOLLOW-UPS (operator exit rule, 2026-11-14)
**Head:** c25b50c
**Date:** 2026-11-14

## Acceptance Criteria

- AC-1: pass. gate.spec.ts and the other bun spec files: 28/28.
- AC-2: pass. branch.test.ts via `claude plugin test` (76/76 kit tests); live session not checked for the branch guard.
- AC-3: pass. run-done-guard-tests.sh 32/32, with new rows for `.specclaw/` in a subfolder (cwd at the subfolder, at the repo root, and an event cwd); live `claude -p` run showed done-guard exit 2 then exit 0 on stop_hook_active.
- AC-4: pass. run-size-cap-tests.sh 65/65, including the new CRLF parity row; base.spec.ts 11/11 parity rows.
- AC-5: pass. run-codex-plugin-tests.sh 54/54; run-mod-tests.sh passes (validate, plugin test).
- AC-6: pass. Docs updated; both suites registered in ci.yml.

## Test Results

All specclaw suites pass except four that fail identically on origin/main on this macOS host
(change-numbering, long-orchestration, phase-state, synth-agent), plus the specclaw-bf and party suites that
also fail on origin/main. shellcheck gate: no new findings.

## Review

Round 17 (since d38ec3d): clean. Round 16 did not run (the backend sent no JSON) and was run again as 17.

Final pass, round 18 (opus): 0 blockers, 1 major, 5 minors. None is an escalated fingerprint. Under the
operator exit rule (one final pass, then no more fixes) each is logged in follow-ups.md:

- major `927ac123fc79` done-guard ties the verify verdict to HEAD by date only; a fast-forward or reset to
  an older-dated commit passes as verified. Fix: record the verified HEAD sha.
- minor `874a5f43f7e9` base fallback chain written twice (branch.ts, base-ref.sh) with no shared test.
- minor `a8d20b31eaee` `git.base_branch: origin/main` works for the size cap and done guard, not the branch guard.
- minor `300dbde69959` every `git merge-base` failure is reported as "no merge-base".
- minor `554d71ba3765` templates/config.yaml names `SIZE_EXCLUDE` but not `SIZE_EXCLUDE_CASED`.
- minor `210b53e59ad3` the branch lookup runs git on every edit, even for exempt targets.

Operator decisions applied before the final pass: the default test list is frozen (`de966eb7f8b9` answered by
`pr.size_exclude`); the done guard looks in the event cwd, then the git toplevel (`b9024b2769a8`); both
base_branch readers strip `\r` (`3bb88cbd75e1`).

## Size

size cap: 400 production lines against origin/main @ 06a78e88a6 (cap 400); over half the cap, consider splitting.
