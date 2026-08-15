# Proposal: Memory-aware parallelism + Playwright browser cap

**Created:** 2026-07-24
**Status:** 🟢 Approved

## Problem

Parallel build agents are good for throughput, but the current concurrency control is a blunt count: `build.parallel_tasks` (default 3) spawns N agents regardless of what's actually running or how much memory the host has. Two failure modes:

1. **Memory blindness.** N agents doing heavy work (large repos, builds, browser-driven verify) can exhaust host RAM. There's no check on available memory before spawning the next agent, so a machine under pressure OOMs or thrashes instead of backing off. Mirrors the class of bug already fixed once in `verify-glob-oom-fix`.

2. **Unbounded Playwright browsers.** When agents run browser-driven verification (`/run`, `/verify`), each can launch a Playwright browser (Chromium ~300–700MB resident each). With M parallel agents each spinning up a browser — plus retries and orphaned instances — concurrent browser count is uncapped. This is the single biggest memory spike in the whole lifecycle and has no hard ceiling.

Net: parallelism should be *adaptive to memory* and browsers should have a *hard, separate limit* independent of agent count.

## Proposed Solution

Two coordinated controls:

1. **Memory-aware agent gating.** Before spawning each agent in a wave, check available system memory against a configurable floor. If free memory is below the floor, hold the spawn until a running agent finishes (or the floor clears). Effective concurrency becomes `min(parallel_tasks, memory_allows)`. Config: `build.memory.min_free_mb` (floor) and optionally `build.memory.per_agent_mb` (est. reservation per agent).

2. **Hard Playwright browser lock.** A global semaphore capping concurrent browser instances at `verify.playwright.max_browsers` (hard default, e.g. 2), enforced regardless of how many agents want one. Agents needing a browser acquire a slot, run, and release — blocking if the cap is hit. Includes cleanup of orphaned browser processes so a crashed agent doesn't leak a slot.

Both surface in `config.yaml` with safe defaults so existing projects don't change behavior unless they opt in.

## Scope

### In Scope
- Memory floor check in the build wave loop (`specclaw-build` / build SKILL step 3c).
- Config keys: `build.memory.min_free_mb`, `build.memory.per_agent_mb`.
- Playwright browser semaphore + config `verify.playwright.max_browsers`.
- Orphaned-browser cleanup on agent failure/exit.
- Docs + defaults in `config.yaml` template.

### Out of Scope
- CPU-based gating (memory only for now).
- Per-agent memory *enforcement* (cgroups/ulimit) — we gate spawns, not hard-kill runaway agents.
- Non-Playwright browsers (Puppeteer, Selenium) — Playwright is the one specclaw drives.
- Distributed / multi-host scheduling.

## Impact

- **Files affected:** ~5–7 (estimated) — `specclaw-build`, build SKILL.md, verify/run skills that launch browsers, `config.yaml` template, a small browser-lock helper (new `bin/` script), tests.
- **Complexity:** medium
- **Risk:** medium — touches the build wave loop (hot path) and adds a blocking semaphore; a buggy lock could deadlock a wave. Needs a timeout/stale-lock escape hatch.

## Open Questions

1. **Memory source:** read `/proc/meminfo` (Linux-only) or something portable? specclaw runs on Linux hosts here — is macOS support required?
2. **Semaphore mechanism:** filesystem lockdir (portable, works across separate agent processes) vs. in-process counter (only works if one orchestrator spawns all)? Agents are separate processes → leans filesystem lock.
3. **Defaults:** what `max_browsers` and `min_free_mb` values? Proposed: `max_browsers: 2`, `min_free_mb: 1024`. Confirm against real host size.
4. **Stale-lock recovery:** how long before a held browser slot is considered orphaned and reclaimed? PID-liveness check vs. TTL?
5. Does the memory floor gate *agent spawns*, *browser acquisitions*, or both? (Proposal assumes both, separate thresholds.)

---

**To proceed:** Review this proposal and approve to begin planning.
