# Verify report: 068-proposal-approved-header

**Verdict:** PARTIAL

PARTIAL means every criterion that can be checked on this machine passes, and two things cannot be proven here:
AC9 (the three existing suites "all pass") and the review loop's fix proof. Both fail for one reason: this Windows
machine already fails the same tests on unmodified HEAD (`f6d45b4`). Nothing in the change causes them. They need a
Linux run (the PR's CI) to be proven.

## Acceptance criteria

- AC-1: pass. A `🟡 Draft` header becomes exactly `**Status:** ✅ Approved`, and only that line changes. Tests H1, H1b; verify agent reproduced it on a fixture.
- AC-2: pass. A second `**Status:**` line in the body is untouched. Test H2.
- AC-3: pass. A second approval leaves the file byte-identical. Test H3.
- AC-4: pass. A header that already says `✅ Approved 2026-11-14` is never rewritten. Test H4.
- AC-5: pass. In a CRLF file the header is flipped and every line is still CRLF. Tests H5a, H5b.
- AC-6: pass. Another phase, another status, no `proposal.md`, no Status line: file unchanged or absent, exit 0, transition recorded. Tests H6a to H6f.
- AC-7: pass. `references/full/propose.md` step 10 mentions the header flip and `specclaw-update-status`. Checked by grep (task T2 report) and by the verify agent.
- AC-8: pass. No file under `.specclaw/changes/` other than this change's own folder differs from `f6d45b4`. Count of other files: 0.
- AC-9: unverified. `run-phase-state-tests.sh` (141 pass, 81 fail), `run-change-size-tests.sh` (63 pass, 1 fail, T16) and `run-done-guard-tests.sh` (20 fail) do not all pass here. The failing sets are identical on unmodified HEAD (checked by running the same suites from `git archive f6d45b4`; HEAD was 112 pass / 81 fail, the change adds only passes). Causes: the suites copy `bash` into a restricted PATH that fails to load on Windows ("error while loading shared libraries"), and the done-guard tests hide `python3`. Needs a Linux run.
- AC-10: pass. All 14 plugin manifests (`.claude-plugin` and `.codex-plugin`) and all 7 marketplace entries read 0.9.17, in their own commit `c67e7b2` (`chore: bump version to 0.9.17`).

## Commands run

- `bash plugins/specclaw/tests/run-phase-state-tests.sh` (exit 1: 141 PASS, 81 FAIL; the 81 are the HEAD baseline; no FAIL line mentions H1 to H13)
- `bash plugins/specclaw/tests/run-change-size-tests.sh` (exit 1: 63 PASS, 1 FAIL, same as HEAD)
- `bash plugins/specclaw/tests/run-done-guard-tests.sh` (exit 1: 20 FAIL, same as HEAD)
- `specclaw-verify size`: 81 production lines against origin/main (cap 400): pass
- No lint or build command is configured for this repo. `shellcheck` is not installed here, so CI's shellcheck gate was not run locally.
- No screenshot step applies (no UI).

Tests pin the fix: run against the script as it was before the review fixes, seven new assertions fail (H7, H8, H10c, H12b, H12c, H13b, H13c).

## Code review

**Code Review:** APPROVED_WITH_NOTES. No BLOCK findings, 2 WARN, 3 NOTE (`review-report.md`).

## Local review loop (specclaw-review)

Review: ESCALATE. 3 rounds, final pass not run, fix proof not proven: the changed tests fail on HEAD (exit 1).

Round 1 found 1 major and 3 minors. Round 2 and 3 found no new defect in the code; they kept the fix-proof item open
and asked for a test of a failed `printf` inside the write loop. All round-1 items were fixed in `a16b533`:

- the header write is now atomic (same-directory temp file made with `cp -p`, then `mv`), with every step checked and warned about;
- only a header that starts with a real approved marker is skipped, so `Not Approved yet` is flipped;
- a missing final newline stays missing;
- every skip warns, and a read-only `proposal.md` is left alone with a warning.

Tests for the failed install (stubbed `mv`) and failed temp copy (stubbed `cp`) were added in `755d8ec`.

Why the loop could not close: `review.fix_proof: block` needs the changed suite to exit 0 at HEAD, which this machine
cannot do for any change to `run-phase-state-tests.sh` (see AC-9). The operator chose to record this and let the PR's
CI on Linux provide the proof, rather than loosen the setting.

## Known gaps and follow-ups

- Not tested: a failed `printf` inside the write loop. `printf` is a bash builtin so it cannot be stubbed; a real test needs `/dev/full` (Linux only). Judged low risk by both reviewers.
- Out of scope, by design: moving a proposal back to pending does not reset the header, and `templates/spec.md` has the same `🟡 Draft` header after plan.
- Existing proposals (active and archived) were deliberately not edited. This change's own `proposal.md` still says `🟡 Draft`, because it was approved before the fix existed.
- Found along the way, not touched: `specclaw-status-row` runs through awk, which on Windows Git Bash strips carriage returns and so rewrites a CRLF `status.md` as LF. The installed plugin cache (0.8.3) also has a corrupt `specclaw-next-change-number`.
