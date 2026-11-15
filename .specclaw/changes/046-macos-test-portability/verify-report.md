# Verify report: 046-macos-test-portability

**Verdict:** PARTIAL. AC-1 to AC-5 pass on macOS. AC-6 (Linux CI) is judged from the diff only and needs the PR's CI run to confirm.

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| AC-1 `run-long-orchestration-tests.sh` exits 0 on macOS | PASS | Exit 0, 272 passed, 0 failed. Baseline on main was 28 FAIL. |
| AC-2 `run-parser-tests.sh` exits 0 on macOS | PASS | Exit 0, 66 passed, 0 failed. Baseline was 5 FAIL. |
| AC-3 `run-change-numbering-tests.sh` exits 0 on macOS | PASS | Exit 0, PASS 162, FAIL 0. Baseline was 6 FAIL. |
| AC-4 `run-phase-state-tests.sh` exits 0 on macOS | PASS | Exit 0, PASS 193, FAIL 0. Baseline was 1 FAIL. |
| AC-5 `run-synth-agent-tests.sh` exits 0 on macOS | PASS | Exit 0, 10 passed, 0 failed. Baseline was 1 FAIL. |
| AC-6 Linux CI stays green | PENDING CI | Judged from the diff only (see below). |

## Commands run (macOS, branch head 41a7c37)

- `bash plugins/specclaw/tests/run-{long-orchestration,parser,change-numbering,phase-state,synth-agent,plugin-split}-tests.sh`: all exit 0.
- Every `plugins/specclaw/tests/run-*-tests.sh` in a loop: 0 failures.
- `bash plugins/specclaw/tests/shellcheck-gate.sh`: no new findings.

## Why AC-6 should hold on Linux

- **`wc`:** GNU `wc -l` prints no padding, so `tr -d ' '` changes nothing. `specclaw-run-long` runs under `set -euo pipefail`, so the `|| echo 0` fallback still fires.
- **`timeout`:** Linux has `timeout`, so `bounded5` and `bounded10` take the original `timeout N` path.
- **`find`:** At maxdepth 1, `find … | sed 's|^\./||'` gives the same names as `-printf '%f\n'`.
- **`stat` and `sed`:** `stat -c` is tried first. `sed -i.bak` works on GNU and BSD, and the `.bak` file is removed.
- **edge1b:** the `mktemp` shim forces the same fallback path that a blocked `TMPDIR` did on GNU.

## Screenshots

None. This change has no UI.

**Code Review:** APPROVED_WITH_NOTES. 3 findings: 0 BLOCK, 0 WARN, 3 NOTE (see `review-report.md`).
**Review loop:** Review: CLEAN — 2 rounds, final pass 41a7c37409, models sonnet/opus; last round 0/0/3 b/M/m
