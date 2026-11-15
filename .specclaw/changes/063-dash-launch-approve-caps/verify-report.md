# Verify Report: 063-dash-launch-approve-caps

**Verdict:** PASS WITH FOLLOW-UPS
**Head:** 0790193 (code); the review records are committed on top of it

## Acceptance criteria

- AC-1: pass. `actions.spec.ts` maps each action to its exact command; `loops.spec.ts` covers approval, the `**Feature:**` module and the proposed-rule rows.
- AC-2: pass. `actions.spec.ts`: change, module, fingerprint, role, number and feature values that fail their pattern throw before a command exists; `pane.test.tsx` refuses `9e4; rm -rf ~` as a cap with no `specclaw-budget set` call.
- AC-3: pass. `pane.test.tsx`: no Confirm before a dry run, after a selection change, or when nothing is launchable; Confirm launches only the items the dry run did not refuse (`064-z`, assigned to someone else, is left out); two presses at once launch once; fleet missing or not set up shows setup steps and no Confirm.
- AC-4: pass. `pane.test.tsx`: a denied Bash call fills the prompt with `specclaw-review learn --apply <fp>`.
- AC-5: pass. `pane.test.tsx`: Approve, Reject, caps list/set and dismissed list/Undo run their commands in order and the mod writes no file; no `specclaw-budget` (exit 127) shows the 065 note and no cap input. `specclaw-budget` is stood in by the test's Bash answer: 065 is not merged.
- AC-6: pass. `run-review-tests.sh`: `learn --reject` stops proposing the lesson, the same lesson is still returned by `memory query`, and rejecting a non-candidate exits 2.
- AC-7: pass. `run-suggest-tests.sh`: `--dismissed` prints the list (exit 1 when the config or lib cannot be read); `--undismiss` removes one feature, keeps the rest and the comment, and every failure path exits 1 with the config unchanged.
- AC-8: pass. `run-mod-tests.sh`: only `$.fs` exists/read/list/stat, no `$.process`, the only `$.tool` call is Bash in `hooks/act.ts`; `claude plugin validate` and `claude plugin test` (19 tests) pass; `run-plugin-split-tests.sh` AC-7 passes (dash absent from the Codex marketplace, metadata-only Codex manifest).

## Commands

- `specclaw-verify size`: 449 production lines, over the 400 cap, with the waiver in `proposal.md` (the 17-manifest version bump is 21 of them; review fixes added the rest).
- All 66 suites in `.github/workflows/ci.yml`, branch (bfede34) vs origin/main (5199148): 52 pass and the same 14 fail on both. Suites changed after bfede34 (dash mod, review, suggest, plugin-split) were re-run at HEAD: all pass.
- `shellcheck-gate.sh`: no new findings.

## Review

- specclaw-review: 8 rounds. Round 6 escalated on `specclaw-suggest --dismiss` without its lib; it keeps exit 0 (059's "a tip never stops a skill" contract) and now says so on stderr. Round 7 clean; round 8 (final, opus) clean 0/0/7. Open minors are in `follow-ups.md`.

Review: CLEAN — 8 rounds, final pass 07901936bc, models sonnet/opus; last round 0/0/7 b/M/m

**Code Review:** APPROVED_WITH_NOTES — 5 findings: 0 BLOCK, 2 WARN (double launch: fixed; version bump: done), 3 NOTE
