# Verification Report: smart-base-branch

**Verified:** 2026-07-16
**Model:** claude-fable-5
**Verdict:** PASS

## Acceptance Criteria

(Quote-first: each verdict cites its evidence line from the test run or code.)

- ✅ **AC1 — origin/HEAD detection.** Test 7a on the bare-origin fixture (default branch `develop`): "PASS: 7a detected base (origin/HEAD) (= 'develop')". PASS.
- ✅ **AC2 — Config override wins.** Test 7d with `base_branch: "release/1.0"`: "PASS: 7d config override wins (= 'release/1.0')" — slashed branch name handled. PASS.
- ✅ **AC3 — No-remote fallback.** Test 7e on a repo with no origin: "PASS: 7e no-remote fallback (= 'main')", no error. PASS.
- ✅ **AC4 — Branch starts at base tip.** Test 7b: "PASS: 7b branch starts at origin/develop tip" — commit-equality assert between `origin/develop` and the created `specclaw/bb-test`. PASS.
- ✅ **AC5 — Resume unchanged.** Test 7c: "PASS: 7c resume warning intact" ("already exists — resuming"). PASS.
- ✅ **AC6 — PR base dynamic.** Test 7f static assert: script contains `--base "$pr_base"` and no `--base main`; `ensure_version_bumped` now calls `detect_base_branch()` (single source of truth). PASS.
- ✅ **AC7 — Config key.** templates/config.yaml: `base_branch: ""` with detection-chain comment under `git:`. PASS.
- ✅ **AC8 — Suite + syntax.** Full run: "19 passed, 0 failed" (13 base + 6 Case 7). `bash -n` clean on specclaw-build and specclaw-pr. PASS.
- ✅ **AC9 — Docs + version.** README config example + "Base Branch Detection" section; CHANGELOG 0.5.3 entry; `"version": "0.5.3"` in both version files. PASS.

## Test Results

```
$ bash plugins/specclaw/tests/run-parser-tests.sh
19 passed, 0 failed  (exit 0)
```

Case 7 exercises a real git topology: bare origin with non-`main` default branch, clone, setup from clone, override, and no-remote repos.

## Issues Found

None. NFR1 (backward compat) evidenced by 7e: `main`-based repos resolve to `main` exactly as before; earlier lifecycle runs on this repo (main-based) behaved identically.

## Summary

**Passed:** 9/9 criteria
**Failed:** 0/9 criteria
**Verdict:** PASS
