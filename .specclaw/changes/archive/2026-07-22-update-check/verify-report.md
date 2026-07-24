# Verification Report: update-check

**Verified:** 2026-07-16
**Model:** claude-fable-5
**Verdict:** PASS

## Acceptance Criteria

(Quote-first: each verdict cites its evidence.)

- ✅ **AC1 — Newer notifies.** Test 8a: "PASS: 8a newer remote notifies" — single line asserted to contain remote version, installed version, and `/plugin update specclaw`. Manual smoke: "⬆ specclaw 9.9.9 available (installed 0.5.0) — update: /plugin update specclaw". PASS.
- ✅ **AC2 — Equal/older silent.** Test 8b: "PASS: 8b equal/older silent" — empty stdout, exit 0 both cases. PASS.
- ✅ **AC3 — Gate wins.** Test 8c with `update_check: false` + `--remote-version 99.0.0`: "PASS: 8c gate disables check". PASS.
- ✅ **AC4 — Unreachable host silent.** Test 8f (script copied beside a manifest pointing at `https://invalid.invalid/nobody/nothing`, `--force`): "PASS: 8f unreachable host silent" — exit 0, empty output. PASS.
- ✅ **AC5 — Cache.** Live run wrote `.specclaw/.update-check` as "1784196444 0.5.0" (epoch + version). Test 8d: fresh seeded cache with 99.0.0 notifies without network ("PASS: 8d cache short-circuit notifies"); test 8e: corrupt epoch ignored ("PASS: 8e corrupt cache ignored"). PASS.
- ✅ **AC6 — Status wiring.** status/SKILL.md step 4: "run `specclaw-check-update .specclaw`... show that line verbatim after the dashboard; if it prints nothing, say nothing." PASS.
- ✅ **AC7 — Suite + syntax.** "19 passed, 0 failed" (13 base + 6 Case 8); `bash -n` clean. PASS.
- ✅ **AC8 — Docs + version.** Template `plugin:` block with commented `update_check: true`; README "Update Check" section incl. gitignore advice; CHANGELOG bullet under [0.5.1]; `"version": "0.5.1"` both files (aligned with PR batch #32–#35). PASS.

## Test Results

```
$ bash plugins/specclaw/tests/run-parser-tests.sh
19 passed, 0 failed  (exit 0)
```

Live network path also exercised against the real repo: published 0.5.0 = installed 0.5.0 → correctly silent, cache written.

## Issues Found

None.

## Summary

**Passed:** 8/8 criteria
**Failed:** 0/8 criteria
**Verdict:** PASS
