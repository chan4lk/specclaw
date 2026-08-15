# Spec: Memory-aware parallelism + Playwright browser cap

**Change:** memory-aware-parallelism
**Created:** 2026-07-24
**Status:** 🟡 Draft

## Overview

specclaw's build wave loop spawns coding agents "up to `build.parallel_tasks`" (default 3) — a fixed count with no regard for host memory. Separately, agents that run browser-driven verification can each launch a Playwright/Chromium instance (~300–700MB resident), with no cap on how many run at once. This change adds two cooperative controls, both opt-in with behavior-preserving defaults:

1. A **memory budget** that lowers effective build concurrency when free RAM is tight.
2. A **hard filesystem semaphore** capping concurrent Playwright browsers independent of agent count.

Enforcement is cooperative — consistent with the rest of specclaw, the shell helpers compute/gate and the SKILL markdown instructs the orchestrating model to honor them.

## Requirements

### Functional Requirements

- **FR1** — A new helper `specclaw-parallel-budget <specclaw_dir>` prints a single integer: the effective concurrency for the current wave, computed as `min(build.parallel_tasks, floor((MemAvailable_mb − min_free_mb) / per_agent_mb))`, clamped to a minimum of 1.
- **FR2** — `specclaw-parallel-budget` reads `MemAvailable` from `/proc/meminfo`. Config keys: `build.memory.min_free_mb` (floor kept free, default 1024) and `build.memory.per_agent_mb` (est. reservation per agent, default 1024).
- **FR3** — When memory config is absent, `specclaw-parallel-budget` returns `build.parallel_tasks` unchanged (default 3) — i.e. opt-in, no behavior change for existing projects.
- **FR4** — The build SKILL wave loop (Step 3c) calls `specclaw-parallel-budget` at the start of each wave and treats its output as the concurrency ceiling for that wave, in place of raw `parallel_tasks`.
- **FR5** — A new helper `specclaw-browser-lock <specclaw_dir> <acquire|release|status>` implements an N-slot filesystem semaphore for Playwright browsers, where N = `verify.playwright.max_browsers` (default 2).
- **FR6** — `acquire` blocks (polls) until a free slot exists, then claims a slot stamped with the caller PID and prints the slot id. `release <slot_id>` frees it. `status` prints slots held / max.
- **FR7** — `acquire` reclaims stale slots whose stamped PID is no longer alive (`kill -0` fails) before deciding the pool is full — a crashed agent must not permanently leak a slot.
- **FR8** — The verify and run guardrails instruct agents to wrap Playwright browser launches with `specclaw-browser-lock acquire` / `release` so the cap is honored during verification.
- **FR9** — `config.yaml` template documents all three new keys with defaults and inline comments.

### Non-Functional Requirements

- **NFR1** — All new shell scripts pass `shellcheck` clean (CI gate: "ShellCheck bin scripts").
- **NFR2** — Helpers degrade gracefully: unreadable `/proc/meminfo`, missing config, or an unwritable lock dir must not crash the build — fall back to `parallel_tasks` / no-cap and continue.
- **NFR3** — `acquire` has a bounded max-wait (timeout) so a wedged pool cannot hang a wave forever; on timeout it proceeds without a slot and warns to stderr (fail-open, memory-safety is best-effort not a deadlock source).
- **NFR4** — No new runtime dependencies beyond coreutils / bash already assumed by existing `bin/` scripts.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — With `min_free_mb: 1024`, `per_agent_mb: 1024`, `parallel_tasks: 3`, and a fixture reporting MemAvailable = 2500MB, `specclaw-parallel-budget` prints `1` (`floor((2500−1024)/1024)=1`).
- **AC2** — With no `build.memory` block in config, `specclaw-parallel-budget` prints `3` (the `parallel_tasks` default) — proving opt-in.
- **AC3** — `specclaw-parallel-budget` never prints `0` or negative — output is clamped to ≥1 even under extreme memory pressure.
- **AC4** — `specclaw-browser-lock acquire` on a fresh pool with `max_browsers: 2` returns a slot; a third concurrent `acquire` (slots 1 and 2 held by live PIDs) blocks until one releases or times out.
- **AC5** — When a slot is held by a dead PID, the next `acquire` reclaims it and succeeds without waiting the full timeout.
- **AC6** — `release <slot_id>` frees the slot; a subsequent `acquire` reuses it. `status` reflects held/max accurately.
- **AC7** — `shellcheck` passes on `specclaw-parallel-budget` and `specclaw-browser-lock` (CI green).
- **AC8** — `config.yaml` template contains `build.memory.min_free_mb`, `build.memory.per_agent_mb`, and `verify.playwright.max_browsers` with documented defaults.
- **AC9** — The build, verify, and run SKILL/guardrail docs reference the two helpers at the correct points (build Step 3c; browser-launch wrap).

## Edge Cases

- `/proc/meminfo` absent (non-Linux) → FR2/NFR2: fall back to `parallel_tasks`, no gating.
- `per_agent_mb` set to 0 → guard against divide-by-zero; treat as "no memory gating" and return `parallel_tasks`.
- Lock dir unwritable → NFR2: warn to stderr, proceed without cap.
- Two agents race for the last slot → atomic claim via `mkdir` (a slot = a directory; `mkdir` is atomic, EEXIST loses the race and retries).
- Agent crashes holding a slot → FR7 stale reclaim via PID liveness.
- `acquire` times out with pool full → NFR3: proceed uncapped, warn.

## Dependencies

- `/proc/meminfo` (Linux). macOS gating is out of scope (falls back to `parallel_tasks`).
- Existing `bin/` conventions (arg parsing, `yaml_val` helper pattern used across specclaw scripts).

## Notes

- Enforcement is cooperative (SKILL-driven), matching specclaw's existing model — helpers gate/compute, the orchestrating model honors them. No cgroups/ulimit hard-kill (out of scope per proposal).
- Semaphore uses a filesystem lockdir because build agents are separate processes; an in-process counter would not see across them.
- Approved defaults (from proposal open questions): filesystem lockdir, `max_browsers: 2`, `min_free_mb: 1024`, `per_agent_mb: 1024`, PID-liveness stale reclaim.
