# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B3] `plugins/specclaw-review/lib/review_core.py:736` `git(..., check=False)` returns an empty string when the diff fails (bad base ref, git error). `touched` is then empty, so every finding is carried with the reason 'its file did not change since the pre-fix commit'. That is a conservative outcome, but the reason is false: the check did not run. Detect a failed diff and label the carry 'could not compare changed files'. (round 2) <!-- fp:b8979d3cb765 -->
- [minor B2] `plugins/specclaw-review/tests/run-review-tests.sh:380` The rename and delete rows run only with `fix_proof: block`, because `fpround` defaults to block. The `warn` branch is untested for GONE findings: it keeps them and lists only the other unproven findings under `unproven`. Add a warn-mode rename row, and a row where a GONE finding and an untouched finding sit in the same round. (round 4) <!-- fp:154df5545a02 -->

## Review tool

- Review tool escalates on rule+file, not on fingerprint: any new finding of an already-seen rule in the same file escalates immediately; fix in a later change. (Rounds 5 and 7: every new B1 in `review_core.py` escalated on first sight.)

## Left open by the operator exit rule (2026-11-14)

Round 5 (`--since 430401f`) and the second final pass (round 7) still reported these majors. The first final pass (round 6) did not run: the backend model refused the request. Two round-7 majors were clear bugs and were fixed once (`6b39fb09d912` renamed tests are dropped from the proof, `893d88fc11e3` recall reads any OSError as a missing file). The rest are logged here.

- [major B1] `plugins/specclaw-review/lib/review_core.py` `_carry`: a finding on a file gone at HEAD is carried in every later round and nothing can clear it. A change whose correct fix is to delete or move the file can then never reach a clean round, in `warn` too. A renamed file can also be reported twice (carried under the old path, re-reported under the new). This is the operator-approved FR-9 behaviour; a later change should resolve the new path (`git diff -M`) or let a human dismiss it. (rounds 5, 7) <!-- fp:f49834c4ae63 --> <!-- fp:a9fd689163c9 -->
- [major B1] `plugins/specclaw-review/lib/review_core.py` `_carry`: the reviewer decides which findings close, and a `--since` diff does not show files the fix did not touch, so silence closes them. In a proven `block` round and in `warn`, a finding in an untouched file closes. This is the operator-approved FR-10 redesign (per-round proof, no line matching). (round 5) <!-- fp:7eb75e14e8ad -->
- [major B1] `plugins/specclaw-review/lib/review_core.py:639` `_proof_due` looks only at the previous round. A plain `run` (no `--since`, no `--final`) after a not-proven round runs no proof and carries nothing, and a final pass after it also skips the proof, so `block` holds only for one order of commands. Decide from the latest round with open unproven findings. (round 7) <!-- fp:08cdf72c9175 -->
