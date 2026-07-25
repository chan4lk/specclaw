# Design: Long-running test orchestration

**Change:** long-running-test-orchestration
**Created:** 2026-07-24

## Technical Approach

Four independent seams, one per root cause, each shaped so the new behaviour is additive and the absent-config path is the current code path.

### 1. `bin/specclaw-run-long` — detached execution with heartbeat

A standalone bin script (not a sourced library) so it is independently testable and callable from both `specclaw-verify` and `specclaw-build` without either sourcing the other.

```
specclaw-run-long [--log-dir DIR] [--phase NAME] [--heartbeat N] [--reuse] -- <command string>
```

Mechanics:

1. Resolve log path `<log-dir>/<phase>-<slug>-<pid>.log` (slug = command sanitized to `[a-z0-9-]`, truncated; PID discriminator per edge case 5).
2. If `--reuse` and a sidecar exists whose `head` matches current HEAD **and** whose `dirty` is `false` and current tree is clean → print the stored tail, echo the stored exit code, return it. No execution.
3. Otherwise: `eval "$cmd" >"$log" 2>&1 &` — keeping `eval` preserves today's metacharacter semantics (edge case 2). Record child PID.
4. Poll loop: `wait -n`-style non-blocking check via `kill -0 "$child"`, sleeping in short ticks and emitting a heartbeat to **stderr** every `heartbeat` seconds. Heartbeat goes to stderr so stdout stays a clean captured payload for callers.
5. `wait "$child"` to harvest the true exit code.
6. Write the sidecar (always, pass or fail), then print the 100-line tail to stdout plus a log-path line.
7. `trap` on INT/TERM: kill the child process **group**, write an interrupted sidecar, exit non-zero (NFR7).

Sidecar is a flat `key=value` file (no `jq` — NFR3):

```
exit=3
duration_s=412
log=/abs/path.log
head=1a2b3c…
dirty=false
cmd=npx playwright test
interrupted=false
```

Heartbeat format, one line, terse enough not to bloat the transcript (NFR4):

```
[run-long] 120s elapsed | 84 log lines | last: Running 140 tests using 1 worker
```

**Why stderr for heartbeats:** `run_capped()` callers in `specclaw-verify` assign stdout to a variable that lands in the verify JSON payload. Heartbeats are for the *agent's* liveness, not the report. Splitting the streams keeps FR3's captured output identical to today (AC6).

### 2. Slow-test tier

`specclaw-verify cmd_collect` currently reads three commands and runs each through `run_capped` (`bin/specclaw-verify:185-214`). Extend to read `build.e2e_command` and `verify.e2e`, then order execution:

```
lint → build → test        (fast gates, unchanged order)
  └─ policy=last:   run e2e only if all three passed
     policy=always: run e2e regardless
     policy=skip:   never run e2e
```

The payload gains `e2e_output` plus an `e2e_state` of `passed | failed | skipped_policy | skipped_gate_failure | not_configured`. A single enumerated state field is what makes FR9 structurally true — there is no "empty output" ambiguity for a reader to misinterpret as success. Unrecognised policy values warn and fall back to `last` (edge case 9).

`skills/verify/SKILL.md` gains the policy semantics so the verify agent reports a skip as a skip.

### 3. Bounded Playwright invocation

New `wrap` subcommand on the existing `specclaw-browser-lock`. It **prints** a transformed command string; it does not execute (NFR6 — testable with no browser, no systemd).

Transformation, in order:

1. Playwright detection: command matches `playwright` → if no `--workers` present, append `--workers=1`. Already-present value is preserved (AC10). Non-Playwright commands skip this step entirely (edge case 13).
2. Project fan-out: for each entry in `verify.playwright.projects`, emit `<cmd> --project=<quoted>`; join with `&&` so they run sequentially in one shell. Empty list → single unmodified invocation (AC12).
3. Memory cap: if `systemd_run_usable` → prefix each invocation with `systemd-run --user --scope -q -p MemoryMax=<max_memory_mb>M`. Usability is *probed*, not assumed from `command -v` (edge case 11): run a trivial `systemd-run --user --scope -q true` once and cache the result for the process. Unusable → emit unwrapped + warn (AC11).

Composition with the rest: `verify` acquires a slot (existing `acquire`), pipes `e2e_command` through `wrap`, hands the result to `specclaw-run-long`, releases the slot. Each script keeps one job: `browser-lock` decides *how the command should be constrained*, `run-long` decides *how it is executed and observed*.

Exit-137 classification (FR13) lives at the reporting boundary in `specclaw-verify`, which knows both the exit code and whether a cap was applied. `wrap` therefore also reports whether it capped — via exit-code convention (`0` = capped, `10` = emitted uncapped) so no second parse of the emitted string is needed.

### 4. PR-aware status

`bin/specclaw-update-status` gains a `pr_state_for <change>` function returning a short rendered string (`PR #123 open`) or empty.

- Resolution order: GitHub via `gh pr list --head <branch> --json number,state,updatedAt` when `gh` is available; else Azure DevOps via the existing auth path; else empty.
- Branch name derives the same way `specclaw-build` does: `<git.branch_prefix><change_name>`, so the lookup matches what specclaw actually pushes.
- Every invocation is wrapped in `timeout 5` and `|| true` (NFR5, and learning `[L2]`: no-match `grep | head | sed` under `set -e` in command substitution aborts the script).
- Multiple PRs → sort by `updatedAt`, take the newest, render its real state (edge case 15).
- A change with an open PR is emitted into the active section with its PR state; the `elif [ -f proposal.md ]` "awaiting planning" branch is reached only when there is no `tasks.md` **and** no PR (AC15).

**Caching:** a lookup result is memoised per run so N changes cost at most N calls, and the whole PR block is skippable via `SPECCLAW_STATUS_NO_PR=1` — which is also the seam the tests use to prove NFR1's unchanged output.

## Architecture

```
verify (skill)
  │
  ├─ specclaw-browser-lock acquire ──────────► slot-N
  │
  ├─ specclaw-browser-lock wrap "<e2e_cmd>" ─► "systemd-run … -p MemoryMax=4096M npx playwright test --workers=1 --project=desktop && …"
  │        exit 0 = capped │ exit 10 = uncapped (warned)
  │
  ├─ specclaw-run-long --phase e2e -- "<wrapped>"
  │        ├─ child: eval → logs/e2e-<slug>-<pid>.log
  │        ├─ stderr: heartbeat every 60s        ← keeps host watchdog satisfied
  │        ├─ stdout: 100-line tail + log path   ← feeds verify payload
  │        └─ logs/e2e-<slug>-<pid>.result       ← survives a teardown
  │
  ├─ specclaw-browser-lock release slot-N
  │
  └─ specclaw-update-status ──► STATUS.md (+ PR state, timeout-bounded, fail-open)
```

Stream discipline is the load-bearing detail: **stderr = liveness, stdout = payload, disk = truth.**

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-run-long` | create | Detached exec + heartbeat + capped tail + HEAD-stamped sidecar (FR1–FR5) |
| `plugins/specclaw/bin/specclaw-verify` | modify | `run_capped()` delegates to `run-long`; add e2e tier + `e2e_state`; exit-137 classification (FR6, FR8–FR9, FR13) |
| `plugins/specclaw/bin/specclaw-build` | modify | `cmd_finalize` test/lint/build via `run-long` instead of bare `eval` (FR6) |
| `plugins/specclaw/bin/specclaw-browser-lock` | modify | New `wrap` subcommand: `--workers=1`, sequential `--project`, `MemoryMax` scope, capped/uncapped exit convention (FR10, FR12) |
| `plugins/specclaw/bin/specclaw-update-status` | modify | PR state per active change, memoised, timeout-bounded, fail-open (FR14) |
| `plugins/specclaw/templates/config.yaml` | modify | `build.e2e_command`, `verify.e2e`, `verify.heartbeat_seconds`, `verify.playwright.max_memory_mb`, `verify.playwright.projects` (FR7, FR11) |
| `plugins/specclaw/skills/verify/SKILL.md` | modify | Document e2e policy + that a skip must be reported as a skip |
| `plugins/specclaw/tests/run-long-orchestration-tests.sh` | create | Regression suite for AC1–AC15 |
| `.github/workflows/ci.yml` | modify | Register the new suite |
| `plugins/specclaw/.claude-plugin/plugin.json` | modify | Version bump |
| `.claude-plugin/marketplace.json` | modify | Version bump (must match plugin.json — CI `json` job asserts) |
| `README.md` / `plugins/specclaw/CLAUDE.md` | modify | Config reference for the five new keys |

## Data Model Changes

**Sidecar file** (new, `key=value`): `exit`, `duration_s`, `log`, `head`, `dirty`, `cmd`, `interrupted`.

**Verify payload** (additive): `e2e_output` (string), `e2e_state` (enum), `e2e_memory_limited` (bool). Existing fields keep their names, types, and values, so an unset `e2e_command` reproduces today's payload byte-for-byte (AC6).

**Config** (all optional, defaults = current behaviour):

```yaml
build:
  e2e_command: ""                  # slow tier; test_command stays the fast tier
verify:
  e2e: last                        # skip | last | always
  heartbeat_seconds: 60
  playwright:
    max_browsers: 2                # existing
    max_memory_mb: 4096            # new
    projects: []                   # new; empty = single invocation, no --project
```

## API Changes

New CLI surfaces (both additive; existing subcommands untouched):

- `specclaw-run-long [--log-dir DIR] [--phase NAME] [--heartbeat N] [--reuse] -- <cmd>` → stdout: capped tail + log path; stderr: heartbeats; exit: the command's exit code.
- `specclaw-browser-lock <dir> wrap <cmd>` → stdout: transformed command string; exit `0` capped / `10` uncapped.

## Key Decisions

1. **`run-long` as a bin, not a sourced function.** Two callers in different scripts; a bin is testable in isolation and avoids cross-sourcing. Cost: one extra process per command — negligible against a multi-minute suite.
2. **Keep `eval`.** The whole point of the existing call sites is that command strings may carry pipes and `&&`. Swapping to an array exec would break real configs for a theoretical hygiene gain.
3. **Heartbeats on stderr.** Only way to add liveness without mutating the captured payload that feeds `verify-report.md` (AC6).
4. **`wrap` prints, does not execute.** Makes every FR10/FR12 assertion a pure string comparison — no browser, no systemd, no network in CI (NFR6).
5. **Operator-declared `verify.playwright.projects`.** Rejected both parsing `playwright.config.*` (TS, not statically tractable) and `npx playwright test --list` (process spawn per verify, needs a working install, new failure mode). One config line beats a fragile inference (Rule 2).
6. **Probe `systemd-run`, don't just detect it.** `command -v` succeeds in containers where `systemd-run --user` fails; the OOM we are fixing is exactly the case where a false-positive cap silently does nothing.
7. **Enumerated `e2e_state` over empty-output sentinel.** Makes "skipped ≠ passed" a type-level property rather than a convention a downstream reader might miss (FR9).
8. **Sidecar refuses reuse on a dirty tree.** HEAD-stamping alone would reuse a stale pass across uncommitted edits — masking the exact change under test (edge case 4).
9. **Reuse is opt-in (`--reuse`).** Default stays "always run". Skipping tests must be an explicit request, never a default inference.
10. **`e2e` default `last`, not `skip`.** `skip` is the safer default for a new consumer but silently weakens the gate; the observed failure shows exactly where that ends — the operator eventually instructed specclaw to skip its own test gate.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Touching the execution path of every build/verify | Every new behaviour is additive and defaults to current code path; AC6/AC11/AC14 exist specifically to prove byte-identical output when config is absent (NFR1) |
| Detached child orphaned or leaking on interrupt | `trap` INT/TERM kills the child process group, writes an interrupted sidecar; AC-covered, mirrors the sleeper-cleanup pattern in `tests/run-memory-parallelism-tests.sh:41-49` |
| `--reuse` masks a real failure | Two independent invalidators (HEAD change, dirty tree) plus opt-in-only; sidecar records both so a wrong reuse is diagnosable |
| `set -e` + no-match `grep` pipeline aborts a script (learning `[L2]`) | `|| true` on every `grep\|head\|sed` inside command substitution; explicit review item in the PR-state task |
| `systemd-run --scope` unavailable in CI, so the cap path goes untested | Test asserts the *emitted string*, not runtime enforcement; a stub `systemd-run` on `PATH` covers the present-case, `PATH` removal covers absent-case |
| Heartbeat noise on fast commands | Nothing emitted before the first interval; a sub-60s command produces zero heartbeat lines (AC3 second half) |
| Wrapping breaks a metacharacter-heavy command | Round-trip test with pipes, `&&`, and env prefixes (edge case 2) |
| PR lookup slows status generation | `timeout 5`, memoised per run, `SPECCLAW_STATUS_NO_PR=1` escape hatch (NFR5) |
| Scope creep across four fixes in one change | Four independently-committable waves; a failure in one leaves the others merged and useful |

## Grounding sources

Discovery (`specclaw-discover-context`) was not runnable in this environment (`Permission denied` on the plugin-cache bin), so grounding came from direct reads of the repo:

- `plugins/specclaw/bin/specclaw-verify:63-81` — `run_capped()` is the exact inline-`eval` seam being replaced; its 100-line cap and `... (truncated, ${total} total lines)` marker are preserved verbatim by FR3.
- `plugins/specclaw/bin/specclaw-build:337-361` — three sequential `if ! eval "$X" >&2 2>&1` blocks; the second `run-long` adoption site.
- `plugins/specclaw/bin/specclaw-browser-lock:7-9` — *"Fail-open: on any degeneracy (unwritable lock dir, acquire timeout) proceed without a slot so a wedged pool can never hang the build (NFR2/NFR3)"* — the fail-open contract NFR2 extends to all four new capabilities.
- `plugins/specclaw/bin/specclaw-update-status:48-51` — the `elif [ -f "$change_dir/proposal.md" ]` → `"proposal ready, awaiting planning"` branch that produced the wrong report; FR14 gates it on PR state.
- `plugins/specclaw/tests/run-memory-parallelism-tests.sh:19-20` — *"Plain bash + coreutils — no jq/bats/npm"* — sets NFR3 and the new suite's shape.
- `.specclaw/learnings.md` `[L2]` — *"Always append `|| true` to grep | head | sed pipelines used inside command substitution"* — applied to the PR-state lookups.
- `plugins/specclaw/CLAUDE.md` (Scripts table) — new bins must be listed there; `.github/workflows/ci.yml:14-19` — new suites must be registered to actually run.
- `CLAUDE.md` (repo root, Version bump rule) — both version files bumped and kept in sync every PR.
