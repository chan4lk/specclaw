# Verify Report: 041-azdo-pr-description-limit

**Verdict:** PASS

**Verified:** 2026-09-27
**Model:** Sonnet 5 (claude-sonnet-5)

## Acceptance Criteria

- ✅ **AC1** — Oversized fixture (untruncated > 8,000 chars) yields output ≤ 3,900 chars.
  Evidence: `bash plugins/specclaw/tests/run-azdo-pr-description-tests.sh` → `PASS: AC1 fixture is genuinely oversized (8113 chars of source)` and `PASS: AC1 description fits default budget (3830 <= 3900)`.

- ✅ **AC2** — Verdict line + footer present in AC1's output, plus a truncation pointer naming a real change-dir file.
  Evidence: `PASS: AC2 verdict line present`, `PASS: AC2 footer present`, `PASS: AC2 truncation pointer(s) present: spec.md staged-files-report.md timeline.md verify-report.md`, and each pointer confirmed against a real file on disk (`PASS: AC2 pointer names a real file (...)` ×4).
  - ⚠️ Edge case (see Issues #1): this AC only exercises the *default* 3900-char budget. At a small-but-legal `azdo.pr_description_max` (a positive integer per FR1), the verdict line/footer guarantee this AC checks can fail — see Issue 1.

- ✅ **AC3** — Small fixture output is byte-identical to the pre-change function.
  Evidence (test): `PASS: AC3 small description unchanged`, `PASS: AC3 no warning under budget`.
  Evidence (independent re-derivation, not just trusting the golden file): extracted `yaml_val`/`extract_section`/`build_pr_description` from `git show main:plugins/specclaw/bin/specclaw-azdo-pr` into a standalone harness, rendered the same small fixture used by the test, and compared byte-for-byte against `plugins/specclaw/tests/fixtures/azdo-pr-description/small.golden`:
    ```
    cmp old.out plugins/specclaw/tests/fixtures/azdo-pr-description/small.golden
    → IDENTICAL to golden (no diff output, empty stderr)
    ```
    This confirms the golden was genuinely captured from the pre-change function, not hand-authored.

- ✅ **AC4** — `azdo.pr_description_max: 1500` in config caps output ≤ 1,500 chars.
  Evidence: `PASS: AC4 description fits 1500 (1460)`, `PASS: AC4 verdict survives a tight budget`, `PASS: AC4 footer survives a tight budget`, plus non-numeric fallback: `PASS: AC4 non-numeric override falls back to 3900 (3830)`.
  - ⚠️ Edge case: only 1500 (comfortably above the danger threshold found in Issue 1) and "banana" (non-numeric) are tested. `0` is not explicitly exercised by an automated case, though the code path (`(( 10#$cfg_max > 0 ))`) visibly handles it the same as non-numeric (falls to 3900 default) — confirmed by code inspection, not by an isolated run (see note in Test Results).

- ✅ **AC5** — A single 10,000-char line still yields output ≤ budget with a stderr `WARNING:`.
  Evidence: `PASS: AC5 description fits (307)`, `PASS: AC5 stderr WARNING emitted`, `PASS: AC5 verdict present`, `PASS: AC5 footer present`.

- ✅ **AC6** — Time accounting shrinks before Summary is touched.
  Evidence: `PASS: AC6 Summary intact (lower sections absorbed the cut)`, `PASS: AC6 Time accounting shrunk first`. Confirmed structurally in code: the shrink order in `fit_description` is `timing_body → staged_body → verify_excerpt → test_lines → ac_text → summary_text`, matching FR3's stated priority exactly.

- ✅ **AC7** — Suite registered in CI; shellcheck gate passes.
  Evidence: `.github/workflows/ci.yml` diff adds
  ```
  + - name: Run azdo PR description tests
  +   run: bash plugins/specclaw/tests/run-azdo-pr-description-tests.sh
  ```
  and `bash plugins/specclaw/tests/shellcheck-gate.sh` exits 0 with `shellcheck: no new findings (23 known, all in the baseline)`.

- ✅ **AC8** — Version bumped in sync, 0.7.7 → 0.7.8, across all three files.
  Evidence:
  ```
  plugin.json:        main=0.7.7  → HEAD=0.7.8
  .codex-plugin/plugin.json: main=0.7.7  → HEAD=0.7.8
  marketplace.json (specclaw entry): main=0.7.7 → HEAD=0.7.8
  ```

## Test Results

Commands actually run (this session), with pass counts:

```
$ bash plugins/specclaw/tests/run-azdo-pr-description-tests.sh
=== 22 passed, 0 failed ===

$ /bin/bash plugins/specclaw/tests/run-azdo-pr-description-tests.sh   # macOS bash 3.2.57
=== 22 passed, 0 failed ===   (identical output to the bash-5 run)

$ bash plugins/specclaw/tests/shellcheck-gate.sh
These baseline entries no longer occur — prune them from shellcheck-baseline.txt:
  plugins/specclaw/bin/specclaw-loop SC2015
shellcheck: no new findings (23 known, all in the baseline)
EXIT=0

$ bash plugins/specclaw/tests/run-change-lock-tests.sh
27 passed, 0 failed

$ bash plugins/specclaw/tests/run-status-row-tests.sh
26 passed, 0 failed

$ bash plugins/specclaw/tests/run-codex-plugin-tests.sh
All Codex plugin package checks passed.
EXIT:0
```

The `shellcheck-gate.sh` "prune" note is a pre-existing, unrelated staleness in `shellcheck-baseline.txt` (`specclaw-loop`, a file this change never touches) — not introduced by this change, and it does not fail the gate (exit 0, no new findings).

AC3's golden-vs-pre-change comparison and a manual reproduction of Issue 1 (below) were done via a hand-built harness in the scratchpad directory (function extraction + fixture rendering), not the checked-in test suite; commands and outputs are quoted inline above and in Issues.

## Issues Found

1. **FR5 ("verdict/footer never removed") is not actually guaranteed once the hard cap fires at a small-but-legal budget** — `fit_description`'s final hard-cap step does `desc="${desc:0:keep}${tail}"` where `keep = max - ${#tail}`. Because `**Verdict:**` sits *before* the hard-cap `tail` in the assembled string, if the shrink loop still leaves the description over budget (all six sections already collapsed to their pointer lines) and `keep` is smaller than the offset of the `**Verdict:**` line, the verdict line is silently dropped from the output — no error, no warning about it specifically. If `max` is smaller than `${#tail}` itself (~28 chars), `keep` clamps to 0 and even the footer text is corring: it gets truncated mid-string (e.g. `🤖 Generated by SpecClaw` becomes `🤖 Generated by `).
   Reproduced directly against the real function (extracted from `plugins/specclaw/bin/specclaw-azdo-pr`, not a mock) using a small synthetic fixture and `azdo.pr_description_max` set via config:
   ```
   max=500 → len=403  has_verdict_lines=1 has_full_footer=1   (fine)
   max=300 → len=300  has_verdict_lines=1 has_full_footer=1   (fine)
   max=150 → len=150  has_verdict_lines=0 has_full_footer=1   (verdict line GONE)
   max=100 → len=100  has_verdict_lines=0 has_full_footer=1
   max=60  → len=60   has_verdict_lines=0 has_full_footer=1
   max=40  → len=40   has_verdict_lines=0 has_full_footer=1
   max=20  → len=20   has_verdict_lines=0 has_full_footer=1   → footer text itself corrupted to "🤖 Generated by " (SpecClaw truncated off)
   ```
   None of AC1–AC8 exercises a budget in this range (AC4 only tests 1500, well clear of the threshold), so no acceptance criterion fails on this evidence — but FR5 is stated unconditionally in the spec ("never removed"), and the implementation does not honor that once the hard cap engages at a tight-but-valid budget. The real-world exposure is bounded (nobody would configure `pr_description_max` in the double digits), but the threshold scales with the change name and file paths baked into the pointer lines, so it is reachable at values someone could plausibly pick (e.g. ~150–400 in a fixture this small; larger in a real repo with long change names). **Fix:** compute `keep` from the position immediately after `**Verdict:** ...` line (or otherwise anchor the verdict line + full footer as fixed, non-shrinkable text) rather than slicing the whole assembled string positionally.

2. **FR7's "under a UTF-8 locale" precondition is asserted by the test harness but never enforced by the production script** — the real `plugins/specclaw/bin/specclaw-azdo-pr` never sets or checks `LC_ALL`/`LANG` (`grep -n "LC_ALL\|LANG=" plugins/specclaw/bin/specclaw-azdo-pr` → no matches); only `run-azdo-pr-description-tests.sh` exports a UTF-8 locale before sourcing the functions. Bash's `${#var}` and `${var:a:b}` both operate byte-wise under a non-UTF-8 locale (e.g. `C`/`POSIX`, common on minimal CI/Docker images). Under such a locale, both the per-section line-boundary shrink and the final hard-cap slice remain internally *consistent* (both count/slice in the same unit), but that unit becomes bytes, not characters — so a hard-cap cut can land mid-way through a multi-byte UTF-8 sequence (e.g. the `🤖` emoji in the fixed footer, or any non-ASCII proposal/spec content), producing invalid UTF-8 in the string handed to `json_escape`. `json_escape`'s primary path (`python3 -c '...sys.stdin.read()...json.dumps(...)'`) would then either raise a decode error (silently swallowed by `2>/dev/null`) and fall through to the byte-blind `sed`-based fallback, which does not validate or fix up the encoding at all — shipping malformed UTF-8 in the JSON body ADO receives. This is exactly the class of "gate passed, then ADO's POST fails" failure this change exists to close, just relocated from length to encoding. Not caught by any AC because the test suite explicitly forces a UTF-8 locale before running. **Fix:** either have `fit_description`/the script's shebang path force `LC_ALL=C.UTF-8` (or detect/require it and warn if unavailable, mirroring the test's own locale-detection loop) before doing any character counting, or explicitly guard the hard-cap slice against splitting a multi-byte sequence.

Neither issue is currently exercised by an acceptance criterion, and both are true edge cases (tiny configured budgets; non-UTF-8 execution locale) rather than defects on the tested path. They are flagged here per the verification brief's explicit instruction to scrutinize `fit_description` for exactly these two failure modes.

## Summary

**Passed:** 8/8 criteria
**Failed:** 0/8 criteria
**Verdict:** PASS

## Post-verify remediation (35403bf)

Both the verifier and the code reviewer raised two non-blocking gaps. Both are fixed in `35403bf`:
- Hard cap could drop the `**Verdict:**` line under a small `azdo.pr_description_max`. The budget now has a 1000-char floor with a warning (test case FR5).
- Under a byte locale the hard cap could split a multi-byte character. Cuts now land on newlines (test case FR7, checked with `iconv` under `LC_ALL=C`).
- Review WARNs addressed too: a body no longer than its pointer is skipped, the dynamic-scoping coupling is documented in a comment, and the warning names section titles.

Re-run: `bash plugins/specclaw/tests/run-azdo-pr-description-tests.sh` → === 28 passed, 0 failed ===; `/bin/bash` (3.2) → === 28 passed, 0 failed ===; shellcheck gate: no new findings. The verdict is unchanged: PASS.

**Code Review:** APPROVED_WITH_NOTES — 7 findings: 0 BLOCK, 3 WARN, 4 NOTE (WARNs 2 and 3 fixed above, WARN 1 documented)
