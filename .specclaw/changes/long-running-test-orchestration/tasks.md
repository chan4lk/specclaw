# Tasks: Long-running test orchestration

**Change:** long-running-test-orchestration
**Created:** 2026-07-24
**Total Tasks:** 12

## Summary

Four independently-committable waves, one per root cause, ordered so each wave leaves the repo green and useful on its own. Wave 1 (detached exec + heartbeat + sidecar) removes the teardown loop and is the highest-value slice. Wave 2 adds the slow-test tier. Wave 3 bounds Playwright's fan-out and memory. Wave 4 fixes status staleness. Wave 5 is docs, CI registration, and the version bump.

Waves 2, 3 and 4 depend on Wave 1 only where they execute commands through `run-long`; Wave 4 is fully independent and may be built in parallel with 2–3 if convenient.

## Tasks

### Wave 1 — Detached execution with heartbeat (root cause 1)

- [x] `T1` — Create `specclaw-run-long`: detached exec, heartbeat, capped tail, HEAD-stamped sidecar
  - Files: `plugins/specclaw/bin/specclaw-run-long`
  - Estimate: large
  - Kind: impl
  - Notes: FR1–FR5. Keep `eval` for the child (edge case 2 — pipes/`&&`/env prefixes must keep working). Heartbeats to **stderr**, capped tail to **stdout**, full log to disk. Sidecar is flat `key=value` (no jq, NFR3) with `exit`/`duration_s`/`log`/`head`/`dirty`/`cmd`/`interrupted`. Log name carries a PID discriminator (edge case 5). `--reuse` requires matching HEAD **and** a clean tree, and refuses when there is no HEAD (edge cases 3, 4). `trap` INT/TERM kills the child process *group* and writes an interrupted sidecar (NFR7). Clamp a 0/non-integer heartbeat to the default (edge case 7). Fall back to `mktemp`, then to inline execution, if the log dir is unwritable (edge case 1, NFR2).

- [x] `T2` — Route `specclaw-verify`'s `run_capped()` through `run-long`
  - Files: `plugins/specclaw/bin/specclaw-verify`
  - Estimate: medium
  - Kind: refactor
  - Depends: T1
  - Notes: FR6. `bin/specclaw-verify:63-81` is the seam. Captured output and exit codes must be unchanged — the existing 100-line cap and `... (truncated, N total lines)` marker are preserved by `run-long`, so the payload stays byte-identical (AC6). Pass `--phase` per command (test/lint/build) and `--log-dir <change_dir>/logs`.

- [x] `T3` — Route `specclaw-build cmd_finalize` test/lint/build through `run-long`
  - Files: `plugins/specclaw/bin/specclaw-build`
  - Estimate: small
  - Kind: refactor
  - Depends: T1
  - Notes: FR6. Three `if ! eval "$X" >&2 2>&1` blocks at `bin/specclaw-build:337-361`. Keep the existing `errors+=(...)` messages verbatim so failure reporting does not shift.

- [x] `T4` — Regression tests for Wave 1
  - Files: `plugins/specclaw/tests/run-long-orchestration-tests.sh`
  - Estimate: medium
  - Kind: test
  - Depends: T1
  - Notes: AC1–AC5 plus edge cases 1–7 and 16. Bash + coreutils only (NFR3); follow the structure of `tests/run-memory-parallelism-tests.sh` (temp workdir, EXIT-trap cleanup, `pass`/`fail` counters, spawned-PID tracking). AC5 needs a side-effecting command (append to a counter file) to prove non-execution on reuse. AC3 uses `--heartbeat 1` against a 3s command, and asserts a sub-interval command emits zero heartbeat lines.

### Wave 2 — Slow-test tier and e2e ordering (root cause 2)

- [x] `T5` — Add `build.e2e_command`, `verify.e2e`, `verify.heartbeat_seconds` to the config template
  - Files: `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Kind: config
  - Notes: FR7. `e2e_command: ""` beside `test_command`; `verify.e2e: last` with the `skip | last | always` values commented; `verify.heartbeat_seconds: 60`. Comments must state that `test_command` is the fast tier and that absent keys mean unchanged behaviour.

- [x] `T6` — Implement e2e policy + `e2e_state` in `specclaw-verify`, and exit-137 classification
  - Files: `plugins/specclaw/bin/specclaw-verify`, `plugins/specclaw/skills/verify/SKILL.md`
  - Estimate: medium
  - Kind: impl
  - Depends: T2, T5
  - Notes: FR8, FR9, FR13. Order lint → build → test, then e2e per policy. Payload gains `e2e_output`, `e2e_state` (`passed|failed|skipped_policy|skipped_gate_failure|not_configured`) and `e2e_memory_limited`. Enumerated state, not an empty-output sentinel — a skip must be structurally un-mistakable for a pass. Unrecognised policy → warn, fall back to `last` (edge case 9); empty `test_command` under `last` is vacuously passing (edge case 10). SKILL.md must tell the verify agent to report a skip as a skip.

- [x] `T7` — Tests for the e2e tier
  - Files: `plugins/specclaw/tests/run-long-orchestration-tests.sh`
  - Estimate: medium
  - Kind: test
  - Depends: T6
  - Notes: AC6–AC9 plus edge cases 8–10. AC6 is the backward-compatibility proof: same fixture with no `e2e_command` must produce byte-identical `collect` output to v0.5.9 — capture the v0.5.9 baseline before T6 lands.

### Wave 3 — Bounded Playwright invocation (root cause 3)

- [x] `T8` — Add `wrap` to `specclaw-browser-lock` + the two new playwright config keys
  - Files: `plugins/specclaw/bin/specclaw-browser-lock`, `plugins/specclaw/templates/config.yaml`
  - Estimate: large
  - Kind: impl
  - Notes: FR10–FR12. `wrap` **prints** the transformed command, never executes it (NFR6). Order: `--workers=1` only for Playwright commands and only when `--workers` is absent (AC10, edge case 13) → one `--project=<quoted>` invocation per `verify.playwright.projects` entry joined with `&&`, single invocation when empty (AC12, edge case 12) → `systemd-run --user --scope -q -p MemoryMax=<N>M` prefix. **Probe** systemd-run usability (run a trivial scope once, cache the result) rather than trusting `command -v` (edge case 11). Exit `0` = capped, `10` = emitted uncapped + warn (NFR2). New keys: `max_memory_mb: 4096`, `projects: []`.

- [x] `T9` — Wire the e2e path through `wrap` and report memory kills
  - Files: `plugins/specclaw/bin/specclaw-verify`, `plugins/specclaw/skills/verify/SKILL.md`
  - Estimate: small
  - Kind: impl
  - Depends: T6, T8
  - Notes: FR13. acquire slot → `wrap` the e2e command → `run-long` it → release slot (release must happen even on failure). Use `wrap`'s exit code to set `e2e_memory_limited`, so an exit `137` under a cap is reported as *memory limit exceeded, cap NM* and the same code without a cap stays a plain failure (AC13).

- [x] `T10` — Tests for `wrap`
  - Files: `plugins/specclaw/tests/run-long-orchestration-tests.sh`
  - Estimate: medium
  - Kind: test
  - Depends: T8
  - Notes: AC10–AC13 plus edge cases 12–13. Pure string assertions. Cover systemd-run present via a stub on `PATH` and absent via `PATH` removal; assert the exit-code convention both ways.

### Wave 4 — PR-aware status (root cause 4)

- [x] `T11` — Add PR state to `specclaw-update-status`, with tests
  - Files: `plugins/specclaw/bin/specclaw-update-status`, `plugins/specclaw/tests/run-long-orchestration-tests.sh`
  - Estimate: medium
  - Kind: impl
  - Notes: FR14, AC14–AC15. `pr_state_for <change>` resolves the branch as `<git.branch_prefix><change_name>`, tries `gh` then Azure, memoises per run, wraps every call in `timeout 5` and `|| true` (NFR5 and learning `[L2]` — a no-match `grep\|head\|sed` in command substitution under `set -e` aborts the script). Newest PR by `updatedAt`, real state rendered — a merged PR must not read as open (edge case 15). The `"proposal ready, awaiting planning"` branch at `bin/specclaw-update-status:48-51` is reachable only with no `tasks.md` **and** no PR. `SPECCLAW_STATUS_NO_PR=1` disables the block and is the seam the byte-identical-output test uses. Tests stub the lookup for both success and failure paths.

### Wave 5 — Docs, CI, release

- [x] `T12` — Register the new suite in CI, document the five new keys, bump the version
  - Files: `.github/workflows/ci.yml`, `README.md`, `plugins/specclaw/CLAUDE.md`, `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Kind: docs
  - Depends: T4, T7, T10, T11
  - Notes: AC16. Add `run-long-orchestration-tests.sh` to the `test` job beside the existing two suites — an unregistered suite silently never runs. Add `specclaw-run-long` to the Scripts table in `plugins/specclaw/CLAUDE.md`. Bump `plugin.json` and `marketplace.json` to the same version (the `json` CI job asserts they match). Confirm `shellcheck` shows no new findings on the changed bins.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
