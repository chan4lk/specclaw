# Spec: Long-running test orchestration

**Change:** long-running-test-orchestration
**Created:** 2026-07-24
**Status:** 🟡 Draft

## Overview

specclaw's build and verify phases execute the project's test/lint/build commands inline via `eval` (`bin/specclaw-verify:71` in `run_capped()`, `bin/specclaw-build:337-361` in `cmd_finalize`). For fast unit suites this is fine. For a Playwright e2e suite it produces a single silent Bash call lasting 4–10+ minutes, which:

- trips the host's agent-silence watchdog (5–7 min) and gets the agent torn down mid-run, discarding all progress;
- streams the full suite output into the agent transcript, inflating it toward the rotation threshold;
- runs Playwright's own project/worker fan-out unconstrained, so the box OOMs (`exit 137`) even at `workers:1`;
- and, when the teardown happens before `specclaw-update-status` runs, leaves `STATUS.md` claiming work that is finished and PR'd is "awaiting planning".

This change makes long command execution **observable while running, bounded in memory, and durable across a teardown**, and adds a slow-test tier so e2e can be ordered last or skipped explicitly rather than by abandoning the gate.

Full evidence and root-cause analysis: `proposal.md`.

## Requirements

### Functional Requirements

**FR1 — `specclaw-run-long` helper.** A new `bin/specclaw-run-long` runs a command string detached from the caller's stdout, writing combined stdout+stderr to a log file, and returns the command's exit code.

**FR2 — Heartbeat progress.** While the command runs, `run-long` emits one progress line to stderr every `verify.heartbeat_seconds` (default `60`): elapsed seconds, log line count, and the last non-empty log line (truncated). No output is emitted before the first interval elapses, so commands faster than one interval stay silent — identical in practice to today's behaviour.

**FR3 — Capped tail, full log on disk.** On completion, `run-long` prints the last `100` lines of the log to stdout (preserving `run_capped`'s existing cap and its `... (truncated, N total lines)` marker) and prints the log path. The complete log stays at `<change_dir>/logs/<phase>-<slug>.log`.

**FR4 — Result sidecar.** Before returning, `run-long` writes `<change_dir>/logs/<phase>-<slug>.result` containing: exit code, duration, log path, the command string, and the repo HEAD commit SHA at start. Written even when the command fails, so a failure is as recoverable as a pass.

**FR5 — HEAD-stamped sidecar reuse.** `specclaw-run-long --reuse` returns a cached sidecar result (skipping execution) only when the sidecar exists **and** its recorded HEAD SHA equals current HEAD. Any new commit invalidates it. Without `--reuse`, the command always runs.

**FR6 — Adoption in verify and build.** `specclaw-verify`'s `run_capped()` and `specclaw-build`'s `cmd_finalize` execute test/lint/build through `specclaw-run-long` instead of bare `eval`. Captured output and exit-code semantics at each call site are unchanged.

**FR7 — Slow-test tier config.** New config key `build.e2e_command` (default `""`), documented in `templates/config.yaml` beside `test_command`. `build.test_command` keeps its current meaning: the fast tier.

**FR8 — E2E policy.** New config key `verify.e2e` with values `skip | last | always`, default `last`.
- `last` — run `lint_command`, `build_command`, and `test_command` first; run `e2e_command` only if all three pass.
- `skip` — do not run `e2e_command`; record it as explicitly skipped.
- `always` — run `e2e_command` unconditionally, alongside the other commands.

**FR9 — Explicit skip reporting.** When e2e is skipped (by policy, or by `last` because an earlier gate failed), the verify payload carries a distinct skipped state with its reason. A skipped e2e must never be reportable as a pass.

**FR10 — Bounded Playwright invocation.** New `specclaw-browser-lock <dir> wrap <command>` prints a transformed command string that: appends `--workers=1` when the command is a Playwright invocation and does not already set `--workers`; and wraps it in a memory-capped scope (`systemd-run --scope -p MemoryMax=<N>M`) when `systemd-run` is available and usable.

**FR11 — Memory cap config.** New config key `verify.playwright.max_memory_mb`, default `4096`, beside the existing `max_browsers`.

**FR12 — Sequential projects.** New config key `verify.playwright.projects` (default `[]`, a list of Playwright project names). When non-empty, `wrap` emits one `--project=<name>` invocation per entry, chained so they run sequentially. When empty, a single invocation is emitted and project selection is left to the project's own Playwright config. specclaw does not parse `playwright.config.*` and does not shell out to enumerate projects.

**FR13 — Memory-kill classification.** When a command run under a memory cap exits `137`, the reported failure states that the memory limit was exceeded and names the cap value. It is never reported as a generic or flaky failure.

**FR14 — PR-aware status.** `specclaw-update-status` includes each active change's PR state in `STATUS.md` (GitHub via `gh`, Azure DevOps via the existing `specclaw-azdo-*` path). A change with an open PR renders as PR-open, never as "proposal ready, awaiting planning".

### Non-Functional Requirements

**NFR1 — Byte-identical default behaviour.** With no new config keys present, no `e2e_command` set, no `systemd-run` available, and no PR discoverable, every observable output must match v0.5.9. This is the acceptance bar, not an aspiration — each of the four conditions gets its own test.

**NFR2 — Fail-open.** Every new capability degrades to the current behaviour rather than blocking a build: unwritable log dir → run inline as today; `systemd-run` missing or unusable → run uncapped; `gh`/`az` missing, unauthenticated, offline, or slow → omit PR state. A wedged new feature must never be able to stall a build. Matches the existing `specclaw-browser-lock` fail-open contract (`bin/specclaw-browser-lock:7-9`).

**NFR3 — Bash + coreutils only.** No `jq`, `bats`, `npm`, or Python runtime dependency in `bin/` or in the test suite, consistent with the existing suites (`tests/run-memory-parallelism-tests.sh:19-20`).

**NFR4 — Transcript economy.** A long command must contribute at most the 100-line tail plus one heartbeat line per interval to the transcript, regardless of how much the suite prints.

**NFR5 — PR-state lookup is bounded.** Status generation must not hang on network calls: each lookup is timeout-bounded and its failure is non-fatal.

**NFR6 — Testability without side effects.** New logic must be testable without launching a browser, contacting a network, or requiring systemd: `wrap` emits a command string rather than executing it, and PR lookups go through an injectable/stubbable seam.

**NFR7 — No orphaned processes.** A `run-long` child must not outlive its parent: interrupted runs clean up the detached process and leave a sidecar recording the interruption.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — `specclaw-run-long` running `sh -c 'echo hi; exit 3'` returns exit 3, prints `hi` in its tail, and writes a log file containing `hi`.
- **AC2** — A command producing 500 lines yields exactly a 100-line tail plus the `... (truncated, 500 total lines)` marker, while the on-disk log holds all 500 lines.
- **AC3** — With `heartbeat_seconds=1`, a 3-second command emits at least 2 heartbeat lines to stderr, each carrying elapsed seconds. A command shorter than one interval emits none.
- **AC4** — After any run, pass or fail, the `.result` sidecar exists and records exit code, duration, log path, command, and a 40-char HEAD SHA.
- **AC5** — `--reuse` with a sidecar whose HEAD SHA matches current HEAD does not re-execute the command (proven by a command with a side effect, e.g. appending to a counter file). After a new commit, the same invocation re-executes.
- **AC6** — With `build.e2e_command` unset, `specclaw-verify collect` output is byte-identical to v0.5.9 for the same fixture. (NFR1)
- **AC7** — `verify.e2e: last` with a failing `lint_command` does not run `e2e_command`, and the payload marks e2e skipped with the failing gate as the reason.
- **AC8** — `verify.e2e: skip` never runs `e2e_command` and marks it explicitly skipped; no code path lets that state read as a pass. (FR9)
- **AC9** — `verify.e2e: always` runs `e2e_command` even when `lint_command` fails.
- **AC10** — `browser-lock wrap 'npx playwright test'` emits a string containing `--workers=1`. Given a command that already contains `--workers=2`, the original value is preserved and not duplicated.
- **AC11** — With `systemd-run` present, the wrapped string contains `MemoryMax=4096M` (or the configured value). With `systemd-run` absent (stubbed off `PATH`), the emitted string is the unwrapped command and a warning goes to stderr. (NFR2)
- **AC12** — With `verify.playwright.projects: [desktop, mobile]`, `wrap` emits two sequential invocations carrying `--project=desktop` and `--project=mobile`. With the key absent, exactly one invocation is emitted and no `--project` flag is added.
- **AC13** — A command exiting `137` under a memory cap is reported with a memory-limit message naming the cap; the same exit code with no cap applied is reported as a plain failure.
- **AC14** — `specclaw-update-status` with a stubbed PR lookup returning an open PR renders that change's line with the PR reference. With the lookup stubbed to fail, output matches the current tasks.md-only rendering and exit status stays 0. (NFR2, NFR5)
- **AC15** — A change directory holding `proposal.md`, `tasks.md` with all tasks `[x]`, and an open PR does not render as "awaiting planning".
- **AC16** — Existing suites `tests/run-parser-tests.sh`, `tests/run-memory-parallelism-tests.sh`, and `tests/run-synth-agent-tests.sh` all still pass, and `shellcheck` reports no new findings on changed `bin/` scripts.

## Edge Cases

1. **Log directory unwritable** — `mkdir -p <change_dir>/logs` fails → warn, fall back to `mktemp`, and if that also fails run inline exactly as today (NFR2).
2. **Command string contains shell metacharacters** — `run-long` must preserve today's `eval` semantics (pipes, `&&`, env prefixes all keep working); wrapping must not re-quote a command into breakage. Round-trip a metacharacter-heavy command in tests.
3. **Not a git repo, or repo with zero commits** — no HEAD SHA to stamp. Sidecar records an empty SHA and `--reuse` refuses to reuse it (fail closed on reuse, since correctness of skipping depends on the stamp).
4. **Uncommitted working-tree changes** — HEAD SHA is unchanged, so a sidecar would be reused despite modified files. Sidecar must additionally record dirty-tree state and refuse reuse when the tree is dirty; otherwise `--reuse` would mask exactly the edit the operator is testing.
5. **Concurrent runs writing the same log path** — two agents verifying the same change and phase. Log/sidecar names must include a discriminator (PID) so neither truncates the other's log.
6. **Heartbeat when the command prints nothing** — log stays empty; heartbeat still emits with elapsed time and an empty-output note. Silence is exactly the case the watchdog kills, so it must still produce a line.
7. **`heartbeat_seconds` set to 0 or a non-integer** — clamp to the default rather than dividing by zero or busy-looping. Mirrors the `per_agent_mb=0` guard already covered in `tests/run-memory-parallelism-tests.sh`.
8. **`e2e_command` set but `verify.e2e` absent** — default `last` applies.
9. **`verify.e2e` set to an unrecognised value** — warn and fall back to `last`; do not fail the run and do not silently skip.
10. **`e2e_command` set, `test_command` empty** — `last` treats the missing fast tier as vacuously passing, then runs e2e.
11. **`systemd-run` on PATH but unusable** — present but fails (no systemd session / permission denied). Detection must probe usability, not mere presence, then fall back uncapped with a warning.
12. **Project name with spaces or shell metacharacters** in `verify.playwright.projects` — quote correctly in the emitted `--project=` flag.
13. **Non-Playwright `e2e_command`** (Cypress, plain script) — `wrap` must not inject `--workers=1`; the memory cap may still apply.
14. **`gh`/`az` present but unauthenticated, or PR lookup slow** — bounded timeout, warn once, omit PR state (NFR5).
15. **Multiple PRs for one change, or a merged/closed PR** — render the most recently updated one and show its actual state; a merged PR must not read as open.
16. **Interrupted `run-long`** — SIGINT/SIGTERM kills the child, writes an interrupted sidecar, leaves no orphan (NFR7).
17. **`grep`/`head`/`sed` pipelines inside command substitution under `set -e`** — a no-match pipeline must not silently abort the script. Known trap from learning `[L2]` in `.specclaw/learnings.md`; append `|| true` on every such pipeline.

## Dependencies

- Existing: `bash` 4+, coreutils, `git`. Optional: `systemd-run` (memory cap), `gh` (GitHub PR state), `az` (Azure DevOps PR state) — all three optional by NFR2.
- Existing scripts touched: `bin/specclaw-verify`, `bin/specclaw-build`, `bin/specclaw-browser-lock`, `bin/specclaw-update-status`, `templates/config.yaml`, `skills/verify/SKILL.md`.
- CI: new test script must be registered in `.github/workflows/ci.yml` alongside the existing two suites.
- Version bump required in `plugins/specclaw/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, kept in sync (enforced by the `json` CI job).
- No dependency on the host health-monitor thresholds in `claude-multi-channel-discord` — specclaw must behave well under the current ones.

## Notes

**Resolved from the proposal's open questions:**

- **Q1 (heartbeat)** → `verify.heartbeat_seconds`, default `60`. `run-long` applies to *all* test/lint/build commands unconditionally rather than above a duration threshold: a threshold needs a duration estimate specclaw does not have, and since nothing is emitted before the first interval, fast commands are unaffected anyway. Simpler and more predictable (guardrail Rule 2).
- **Q2 (memory cap)** → `verify.playwright.max_memory_mb`, default `4096`, not derived from `build.memory.per_agent_mb`. Locked at approval.
- **Q3 (sidecar staleness)** → HEAD-commit stamping, plus the dirty-tree refusal from edge case 4. Locked at approval.
- **Q4 (`verify.e2e` default)** → `last`. Locked at approval.
- **Q5 (project enumeration)** → neither option. Parsing `playwright.config.*` (TS/JS) is not statically tractable and `npx playwright test --list` costs a process spawn per verify and needs a working install. Instead the operator declares `verify.playwright.projects` explicitly (FR12), empty by default. Zero new failure modes; costs one config line in the projects that need serialization.
- **Q6 (single change)** → confirmed, with the four parts as independently-committable waves.

**Deliberately out of scope:** non-idempotent Playwright fixtures in a consumer project (fixed, non-randomized entity names leaving orphaned rows → HTTP 409 conflicts on re-run) belong to that project, not specclaw. Fixing FR1–FR6 removes most of the mid-test kills that create those orphans.
