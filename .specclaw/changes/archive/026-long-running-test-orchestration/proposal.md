# Proposal: Long-running test orchestration

**Created:** 2026-07-24
**Status:** ✅ Approved (2026-07-24)

## Problem

On a downstream consumer project — a TypeScript web app with a two-project (mobile + desktop) Playwright e2e suite, driven from a chat-bridged agent session — specclaw's build/verify phases became effectively unusable for roughly a week of operator wall-clock time. The failure was not a single bug but four interacting defects, all observed over a ~48h window:

- **9 agent teardowns** — repeating pattern `⏳ still working (5 min since last reply)` → `⚠️ agent stopped responding (no reply for 6 min). Tearing down`. One instance went 39 min before teardown.
- **7 session rotations** at 519 KB / 556 KB / 797 KB / 819 KB / 886 KB / 1040 KB / 1156 KB transcripts.
- **Repeated Playwright OOM kills** — `exit 137`, "got SIGKILL'd (OOM) even w/ workers:1".
- **Wrong status reporting** — STATUS.md claimed four consecutive changes were "awaiting planning" when all four were already built, verified and PR'd.

Net effect: the operator repeatedly asked for current status, got a stale or re-derived answer, and eventually instructed specclaw to *skip its own test gate* to escape the deadlock. A quality gate that gets disabled under pressure is worse than no gate.

### Root cause 1 — blocking inline e2e triggers the host watchdog

`plugins/specclaw/bin/specclaw-verify` and `plugins/specclaw/bin/specclaw-build` (finalize, ~lines 327-362) run `build.test_command` inline via `eval`. A Playwright suite is one Bash call lasting 262 s, 596 s, or longer, emitting nothing to the transcript until it exits. The host (claude-multi-channel-discord health monitor) treats 5–7 min of agent silence as a hung session and tears the agent down — mid-run, losing all progress. The next message respawns a fresh agent that starts the same suite from zero. This is the single largest time sink in the log.

### Root cause 2 — no slow-test tier

`plugins/specclaw/templates/config.yaml:47-49` defines exactly one `test_command` alongside `lint_command` and `build_command`. There is no separate slow/e2e tier and no policy knob, so when the operator asked twice for e2e to be deferred to the end of the run so it would stop OOM-ing the box, specclaw had no configuration surface capable of honouring either request. The only available workaround was abandoning the test gate entirely.

### Root cause 3 — OOM survives the v0.5.9 browser cap

v0.5.9 added `plugins/specclaw/bin/specclaw-browser-lock` with `verify.playwright.max_browsers` (default 2). That semaphore gates *specclaw's own parallel agents* — it does not constrain what happens inside a single slot. The consumer project's Playwright config declares two projects (mobile + desktop), so one lock slot still fans out to concurrent Chromium instances, and the box still OOM'd at `workers:1`. Because the OOM killer targets the whole process tree, the failure surfaces as an opaque `exit 137` with no test output — and both operator and agent initially read that as test flakiness rather than a memory kill, which sent the investigation down the wrong path.

### Root cause 4 — status derived from tasks.md alone

`plugins/specclaw/bin/specclaw-update-status` computes phase state from `tasks.md` completion counts within each active change directory. It never inspects PR state. So a change whose work is finished and PR'd, but whose `status.md` was never written back (because the agent was torn down before step 6), shows as un-started. After each session rotation the fresh agent re-investigated the whole backlog from scratch to reconstruct the truth — expensive, and it produced contradictory answers to the same operator question within minutes.

## Proposed Solution

Four coordinated changes, one per root cause. They share a single theme: **long-running commands must be observable while they run, bounded in what they can consume, and their outcome must be durable across a session teardown.**

### 1. `run_long()` — detached execution with heartbeat

New shared helper (a `specclaw-run-long` bin, sourced by `specclaw-verify` and `specclaw-build`) that replaces inline `eval` for any command expected to exceed a threshold:

- Launch the command detached, redirecting stdout+stderr to `.specclaw/changes/<change>/logs/<phase>-<cmd>.log`.
- Poll for completion. On each poll interval (~60 s default), emit one short progress line (elapsed time, log line count, last non-empty line) so the agent stays visibly alive and the host watchdog never fires.
- On exit, tail only the last N lines (reuse the existing 100-line cap from `specclaw-verify:185-214`) into the transcript; the full log stays on disk and is referenced by path.
- Write a small sidecar result file (exit code, duration, log path) *before* returning, so a teardown mid-poll leaves a recoverable record instead of nothing.

The sidecar is what makes this survive teardown: a respawned agent reads the result rather than re-running a 10-minute suite.

### 2. `build.e2e_command` + `verify.e2e` policy

- New config key `build.e2e_command` (default `""`) for the slow tier. `build.test_command` keeps its current meaning: fast tests only.
- New config key `verify.e2e` with values `skip | last | always`, default `last`.
  - `last` — run lint, build, and fast tests first; run e2e only once those pass, as the final gate. Directly implements the operator's "run e2e at the end".
  - `skip` — record e2e as skipped in `verify-report.md` (explicitly, not silently) and continue.
  - `always` — current behaviour.
- Absent `e2e_command` → behaviour is byte-identical to today, so existing consumers are unaffected.

### 3. Bound Playwright's own fan-out and its memory

Extend `specclaw-browser-lock` so holding a slot also constrains what runs inside it:

- Force `--workers=1` when invoking a detected Playwright command, and iterate declared projects sequentially rather than letting Playwright run them concurrently.
- Run the suite inside a memory-capped scope (`systemd-run --scope -p MemoryMax=…` where available, with a documented no-op fallback where it is not). This converts "OOM killer takes down the box and every sibling agent" into "this one command fails with a diagnosable error", which is the difference between a lost hour and a lost afternoon.
- Surface the distinction explicitly: an `exit 137` under a memory cap must be reported as *memory limit exceeded*, never left to be guessed at as flakiness.

### 4. PR-aware status

Teach `specclaw-update-status` to fold PR state into `STATUS.md`: for each active change, look up its PR (GitHub via `gh`, Azure DevOps via the existing `specclaw-azdo-issue` path) and show that state alongside task counts. A change that is built, verified and PR'd must never render as "awaiting planning". Lookups must degrade gracefully — no network, no auth, or no PR yields the current tasks.md-only output rather than an error.

## Scope

### In Scope

- New `specclaw-run-long` helper; adopt it in `specclaw-verify` and `specclaw-build` finalize for test/lint/build execution.
- Per-command log files + result sidecars under `.specclaw/changes/<change>/logs/`.
- New config keys: `build.e2e_command`, `verify.e2e` (`skip|last|always`). Documented in `templates/config.yaml`.
- E2E ordering in the verify phase (last gate, after lint/build/fast tests pass).
- `specclaw-browser-lock`: forced `--workers=1`, sequential project iteration, optional memory-capped scope, explicit OOM reporting.
- `specclaw-update-status`: PR state in `STATUS.md`, with graceful degradation.
- Regression tests extending `plugins/specclaw/tests/run-memory-parallelism-tests.sh` (or a sibling script): heartbeat emission, sidecar recovery, e2e policy branches, OOM classification, status output with and without PR data.
- Docs: README / CLAUDE.md config reference for the new keys.

### Out of Scope

- Fixing non-idempotent e2e fixtures in a consumer project. Where a spec uses fixed (non-randomized) entity names, a run killed mid-test never fires its `finally` cleanup and leaves orphaned rows that cause HTTP 409 conflicts on the next run. Real bug, but it belongs to the consumer project, not specclaw. (Worth noting: fixing root cause 1 largely stops the mid-test kills that create those orphans.)
- Changing the host health-monitor thresholds in `claude-multi-channel-discord`. Different repo. specclaw should be well-behaved under the existing thresholds rather than demand they be raised.
- Any change to `build.parallel_tasks`, `build.memory`, or the v0.5.9 memory budgeting maths — that layer works; the gap is inside a slot, not in slot allocation.
- Retry/quarantine logic for genuinely flaky tests.

## Impact

- **Files affected:** ~8 (estimated) — new `bin/specclaw-run-long`; edits to `bin/specclaw-verify`, `bin/specclaw-build`, `bin/specclaw-browser-lock`, `bin/specclaw-update-status`, `templates/config.yaml`, `skills/verify/SKILL.md`, plus tests
- **Complexity:** medium
- **Risk:** medium — touches the execution path of every build and verify run. Mitigated by making every new behaviour opt-in or default-identical: no `e2e_command` set → unchanged; no `systemd-run` available → unchanged; no PR found → unchanged status output.

## Open Questions

**Resolved at approval (2026-07-24)** — operator approved without amending; these are the decisions planning proceeds on:

- **Q2 memory cap** → new key `verify.playwright.max_memory_mb`, default `4096`, explicitly configurable. Fixed default rather than derived from `build.memory.per_agent_mb`: verify runs one suite at a time and should not inherit build's per-agent sizing, which would couple the two phases for no gain.
- **Q3 sidecar staleness** → HEAD-commit stamping. A sidecar is trusted only while the change's HEAD commit is unchanged; any new commit invalidates it. A TTL would let a stale pass survive a code change, which is the exact class of wrongness this proposal exists to remove.
- **Q4 `verify.e2e` default** → `last`, as proposed.
- **Q6 single change** → confirmed. Planning must keep the four parts as independently-committable waves.

Still open, decide during `/specclaw:plan`:

1. **Heartbeat interval and threshold.** 60 s poll assumes the host's ~5 min silence threshold. Should the interval be configurable (`verify.heartbeat_seconds`), and should `run_long()` kick in above a duration threshold or unconditionally for all test/lint/build commands? Unconditional is simpler and more predictable; the cost is a heartbeat line on fast commands that do not need one.
2. **Memory cap value.** Fixed default (e.g. 4096 MB), a fraction of `MemAvailable`, or derived from the existing `build.memory.per_agent_mb`? Deriving keeps one source of truth but couples verify to build config.
3. **Sidecar staleness.** How long may a respawned agent trust an existing result sidecar before re-running? Options: trust while the change's HEAD commit is unchanged (precise, needs commit stamping), or a simple TTL (crude but trivial). Commit-stamping seems right given the failure mode being fixed.
4. **`verify.e2e` default.** `last` is proposed. `skip` would be safer for first-run consumers but silently weakens the gate — and the log shows exactly how that ends. Confirm `last`.
5. **Project enumeration.** Reading Playwright projects requires parsing `playwright.config.*` (TS/JS, not statically trivial) or calling `npx playwright test --list`. The latter is more robust but costs a process spawn per verify. Preference?
6. **Scope check.** Four fixes in one change means one PR touching the whole build/verify execution path. Confirmed as a single proposal — flagging that task ordering in `/specclaw:plan` should keep them as independently-committable waves so a problem in one does not block the others.

---

**To proceed:** Review this proposal and approve to begin planning.
