# Verify Report: long-running-test-orchestration

**Verdict:** PARTIAL
**Date:** 2026-07-25

## Summary

The implementation covers all 16 acceptance criteria structurally. 261 of 261 tests in the new `run-long-orchestration-tests.sh` suite pass; the existing memory-parallelism suite (16/16) is unaffected. The core paths for AC1–AC15 were confirmed both by code reading and by targeted live-shell verification (AC6 byte-identical golden, AC13 cap-detection logic, AC15 rendering). Two items could not be fully verified in this environment: `shellcheck` is absent locally (AC16 "no new shellcheck findings" sub-criterion), and the "existing suites still pass" portion of AC16 is partially degraded by a pre-existing `jq: command not found` failure in `run-parser-tests.sh` that also exists on `origin/main`. CI (`ci.yml`) registers the new suite and runs `shellcheck` on every push, which is the appropriate gating mechanism for those two gaps.

## Acceptance Criteria

| AC | Verdict | Evidence |
|----|---------|----------|
| AC1 — `run-long` exits 3, tail holds `hi`, log on disk | MET | `run-long-orchestration-tests.sh` Case 1–2; code path `specclaw-run-long:291` |
| AC2 — 500 lines → 100-line tail + truncation marker, 500 on disk | MET | Case 3–4; `specclaw-run-long:280-287` |
| AC3 — heartbeat_seconds=1 → ≥2 heartbeat lines; sub-interval → none | MET | Case 5–6; `specclaw-run-long:237-254` |
| AC4 — `.result` sidecar on pass and fail with all required keys | MET | Cases 8–9; `specclaw-run-long:268-276`; sidecar key set confirmed (`exit`, `duration_s`, `log`, `head`, `dirty`, `cmd`, `interrupted`) |
| AC5 — `--reuse` hits on matching clean HEAD, misses after commit | MET | Cases 10–13; dirty-tree, empty-HEAD, and cached-dirty paths each have a separate case with a side-effecting counter file |
| AC6 — no e2e keys → payload byte-identical to v0.5.9 | MET | Case 28 (golden comparison); confirmed live: `yaml_has_key` returns false for both `e2e_command` and `e2e` on the baseline fixture; `e2e_json` emitted only under `e2e_configured=true` (`specclaw-verify:420`) |
| AC7 — `last` + failing lint skips e2e, names the gate | MET | Case 30; `specclaw-verify:354-362`; `e2e_state=skipped_gate_failure`, failing gate named in `e2e_output` |
| AC8 — `skip` never runs e2e, cannot read as a pass | MET | Case 29; `e2e_state=skipped_policy`, `e2e_output` contains "This is NOT a pass"; all five skip states carry an explicit not-a-pass annotation in their output strings (`specclaw-verify:347-348`, 350-351, 362`) |
| AC9 — `always` runs e2e even when lint failed | MET | Case 31; marker file written despite `lint_passed=false`; `e2e_state=passed` in payload |
| AC10 — `wrap` appends `--workers=1`; existing `--workers` preserved | MET | Cases 43 (both `--workers=2` and space-separated `--workers 4` forms); `specclaw-browser-lock:324` |
| AC11 — `systemd-run` present → `MemoryMax=4096M`; absent/unusable → unwrapped + warning | MET | Cases 41–42; both "missing from PATH" and "present-but-failing" paths tested separately; `systemd_run_usable()` probes with a live invocation (`specclaw-browser-lock:219-227`) |
| AC12 — projects fan-out; absent/empty → single invocation, no `--project` | MET | Cases 45–47 (inline flow and block sequence forms); empty list case confirmed |
| AC13 — exit 137 under cap → memory-limit message with cap value; same code without cap → plain failure | MET | Cases 37–38; cap detection at `specclaw-verify:374,379-380` (`wrap_rc -eq 0` AND `MemoryMax=` in wrapped string); uncapped path (wrap_rc=10) leaves `e2e_cap` empty so exit 137 is a plain failure |
| AC14 — stubbed open PR renders in line; stubbed failing lookup → unchanged output, exit 0 | MET | Cases 19–20; failing stub confirmed byte-identical to `SPECCLAW_STATUS_NO_PR=1` baseline |
| AC15 — all-[x] tasks + open PR never renders as "awaiting planning" | MET | Case 22; delta (tasks + PR) and epsilon (proposal-only + PR) both confirmed active, not pending; live run confirmed the STATUS.md text |
| AC16 — existing suites pass; shellcheck no new findings | UNVERIFIED | New suite registered in `ci.yml:21`; parser suite has pre-existing 11 failures due to `jq: command not found` on this machine (identical on `origin/main` — not a regression); `shellcheck` not installed locally |

## Test Results

| Suite | Result |
|-------|--------|
| `tests/run-long-orchestration-tests.sh` | 261 passed, 0 failed |
| `tests/run-memory-parallelism-tests.sh` | 16 passed, 0 failed |
| `tests/run-parser-tests.sh` | 30 passed, 11 failed — `jq: command not found`; identical failure count on `origin/main`; not a regression from this branch |
| `shellcheck plugins/specclaw/bin/specclaw-*` | Cannot run — `shellcheck` not installed on this machine; runs in CI (`ci.yml:29`) |

## Findings

1. **`e2e_configured` detection is narrow** (`specclaw-verify:299`): the gate fires on `e2e_command` or `e2e` keys anywhere in the file, not scoped to `build.` / `verify.`. A config with an unrelated comment containing "e2e_command:" would falsely set `e2e_configured=true`. In practice the config format does not produce this, and the test suite confirms the baseline case (AC6). Low risk, not a regression from spec intent.

2. **`failed` count shows "| 0 failed"** when `failed=0` in `specclaw-update-status:121`. The string `${failed:+| $failed failed}` expands to `| 0 failed` because `"0"` is a non-empty string in bash. The test in Case 22 accounts for this ("**delta** — 2/2 tasks (100%) | 0 failed | PR #11 open") so the output is correct-by-spec. Slightly noisy but consistent with what the tests assert; not a bug per the spec.

3. **`specclaw-gh-sync` change is in scope** (modified in the diff). The change adds a sentinel write to `status.md` when GitHub Issues are disabled. This is outside the spec for `long-running-test-orchestration` and carries no tests in this suite. No AC is at risk, but it is an untracked scope addition.

## Unverified in this environment

- **`shellcheck` findings on changed `bin/` scripts** — `shellcheck` is not installed locally. The CI `shellcheck` job runs on every push with `shellcheck plugins/specclaw/bin/specclaw-* || true` (note: `|| true` means CI does not block on findings; findings are advisory only).
- **Real Playwright / systemd run** — No browser installed; all Playwright and `systemd-run` paths are covered by stubs per NFR6.
- **`run-parser-tests.sh` baseline** — 11 tests fail due to `jq` absent on this machine; failure is pre-existing on `origin/main` and not caused by this branch.
