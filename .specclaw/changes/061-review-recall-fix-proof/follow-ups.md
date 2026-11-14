# Follow-ups

Deferred by the review loop: minors and pre-existing findings.

- [minor B3] `plugins/specclaw-review/lib/review_core.py:736` `git(..., check=False)` returns an empty string when the diff fails (bad base ref, git error). `touched` is then empty, so every finding is carried with the reason 'its file did not change since the pre-fix commit'. That is a conservative outcome, but the reason is false: the check did not run. Detect a failed diff and label the carry 'could not compare changed files'. (round 2) <!-- fp:b8979d3cb765 -->
- [minor B2] `plugins/specclaw-review/tests/run-review-tests.sh:380` The rename and delete rows run only with `fix_proof: block`, because `fpround` defaults to block. The `warn` branch is untested for GONE findings: it keeps them and lists only the other unproven findings under `unproven`. Add a warn-mode rename row, and a row where a GONE finding and an untouched finding sit in the same round. (round 4) <!-- fp:154df5545a02 -->
