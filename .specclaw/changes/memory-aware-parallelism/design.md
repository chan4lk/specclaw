# Design: Memory-aware parallelism + Playwright browser cap

**Change:** memory-aware-parallelism
**Created:** 2026-07-24

## Technical Approach

Two independent shell helpers plus SKILL/config wiring. Both follow the existing `bin/` conventions: bash, `set -euo pipefail`, positional `<specclaw_dir>` first arg, `yaml_val` for config reads, shellcheck-clean.

1. **`specclaw-parallel-budget`** — pure computation, no state. Reads `MemAvailable` (kB) from `/proc/meminfo`, converts to MB, reads the three build config values, and prints `clamp≥1( min(parallel_tasks, floor((mem_avail − min_free)/per_agent)) )`. Falls back to `parallel_tasks` whenever memory info or config is missing/degenerate. The build SKILL calls it once per wave and uses the number as that wave's concurrency ceiling.

2. **`specclaw-browser-lock`** — N-slot counting semaphore backed by a lock **directory** per slot (`mkdir` is atomic on POSIX, so it's the race-safe primitive — no `flock` dependency). Slots live under `<specclaw_dir>/.locks/playwright/slot-<i>/`, each containing a `pid` file. `acquire` scans slots: a slot is free if its dir is absent *or* its stamped PID is dead (`kill -0` fails → reclaim). It claims via `mkdir slot-<i>` (loser of a race retries the scan). Polls with a bounded timeout; fail-open on timeout. `release` removes the slot dir. `status` counts live slots.

Enforcement is cooperative: the build SKILL honors the budget number, and the verify/run guardrails tell browser-launching agents to bracket their Playwright usage with acquire/release. This matches every other specclaw control (the shell computes, the SKILL-driven model obeys).

## Architecture

```
Wave start ──▶ specclaw-parallel-budget .specclaw ─▶ N  (effective concurrency)
                       │ reads /proc/meminfo + build.memory.* + build.parallel_tasks
                       ▼
   build SKILL 3c: spawn ≤ N agents this wave

Agent doing browser verify:
   specclaw-browser-lock .specclaw acquire ─▶ slot-2   (blocks if pool full; reclaims dead slots)
     └─ launch Playwright … run … ─┐
   specclaw-browser-lock .specclaw release slot-2 ◀────┘
        pool = verify.playwright.max_browsers slots under .specclaw/.locks/playwright/
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-parallel-budget` | create | Memory-aware effective-concurrency calculator (FR1–FR3). |
| `plugins/specclaw/bin/specclaw-browser-lock` | create | N-slot filesystem semaphore: acquire/release/status (FR5–FR7). |
| `plugins/specclaw/templates/config.yaml` | modify | Add `build.memory.{min_free_mb,per_agent_mb}` + `verify.playwright.max_browsers` with defaults & comments (FR9). |
| `plugins/specclaw/skills/build/SKILL.md` | modify | Step 3c: call `specclaw-parallel-budget` at wave start, honor it as the ceiling (FR4). |
| `plugins/specclaw/references/agent-guardrails.md` | modify | Add rule: wrap Playwright launches with `specclaw-browser-lock` acquire/release (FR8). |
| `plugins/specclaw/skills/verify/SKILL.md` | modify | Reference the browser-lock wrap where browser-driven verification is described (FR8/AC9). |
| `plugins/specclaw/tests/` | create/modify | Regression tests for both helpers + wire into the parser test runner (NFR1, AC1–AC7). |

_(The verify SKILL edit is conditional on that skill actually describing browser launches; if it doesn't, the guardrails edit alone satisfies FR8 and the verify edit is dropped — noted in tasks.)_

## Data Model Changes

None. New config keys only (documented in template). Lock state is ephemeral filesystem dirs under `.specclaw/.locks/` (git-ignored territory — add to `.gitignore` if not already covered by `.specclaw/` patterns).

## API Changes

Two new CLI helpers (contracts above). No changes to existing helper signatures.

## Key Decisions

- **Filesystem lockdir over in-process counter** — build agents are separate OS processes; only a filesystem primitive is visible across them. `mkdir` chosen over `flock` for atomicity without a `flock` binary dependency (NFR4).
- **Fail-open, not fail-closed** — memory gating and the browser cap are best-effort safety, not correctness gates. On any degeneracy (no `/proc/meminfo`, unwritable lock dir, acquire timeout) the helpers let the build proceed rather than deadlock or abort (NFR2/NFR3). Rationale: a stuck build is worse than an occasional over-subscription.
- **Opt-in defaults preserve current behavior** — absent config → `parallel_tasks` unchanged, no cap enforced beyond the documented defaults. Existing projects see no change unless they set the keys.
- **Cooperative enforcement** — consistent with specclaw's SKILL-driven model; avoids a heavyweight supervisor process.
- **Clamp ≥1** — memory pressure can shrink concurrency but never stall the wave to zero agents.

## Risks & Mitigations

- **Deadlock in the wave loop from a wedged semaphore** (medium) → bounded acquire timeout + fail-open (NFR3); stale-PID reclaim (FR7).
- **Race on the last slot** (medium) → atomic `mkdir` claim; EEXIST loser retries the scan (edge case covered).
- **Divide-by-zero / degenerate config** (low) → guard `per_agent_mb==0` → treat as no gating (edge case).
- **Non-Linux host** (low) → `/proc/meminfo` absent → fall back to `parallel_tasks` (out-of-scope macOS, documented).
- **Cooperative enforcement can be ignored by a non-compliant agent** (low, accepted) → this is the same trust model as the rest of specclaw; hard enforcement (cgroups) is explicitly out of scope.

## Grounding sources

- `plugins/specclaw/skills/build/SKILL.md` L59 — "Run independent tasks in parallel up to `parallel_tasks`." — the exact hook where the budget ceiling replaces the raw count (FR4).
- `plugins/specclaw/bin/specclaw-build` L165, L174 — `parallel_tasks="$(yaml_val "$config" "build.parallel_tasks")"` / `parallel_tasks="${parallel_tasks:-3}"` — confirms config path and default 3 (FR3).
- `plugins/specclaw/templates/config.yaml` L46–L51 — existing `build:` block with `parallel_tasks: 3` — where the new `memory:` sub-block and `verify.playwright` land (FR9).
- `plugins/specclaw/references/agent-guardrails.md` — existing numbered agent rules — the file the browser-lock wrap rule is appended to (FR8).
