# Tasks: Memory-aware parallelism + Playwright browser cap

**Change:** memory-aware-parallelism
**Created:** 2026-07-24
**Total Tasks:** 5

## Summary

Two new shell helpers (`specclaw-parallel-budget`, `specclaw-browser-lock`), config-template additions, SKILL/guardrail wiring, and regression tests. Wave 1 builds the independent pieces (two helpers + config) in parallel; Wave 2 wires them into the SKILL docs and adds tests.

## Tasks

### Wave 1 — Independent building blocks

- [x] `T1` — Create `specclaw-parallel-budget` helper
  - Files: `plugins/specclaw/bin/specclaw-parallel-budget`
  - Estimate: medium
  - Kind: impl
  - Notes: Reads `MemAvailable` from `/proc/meminfo` (kB→MB), config `build.memory.min_free_mb` (def 1024), `build.memory.per_agent_mb` (def 1024), `build.parallel_tasks` (def 3). Prints `clamp≥1(min(parallel_tasks, floor((mem_avail−min_free)/per_agent)))`. Fall back to `parallel_tasks` when `/proc/meminfo` missing, no `build.memory` block, or `per_agent_mb==0`. `set -euo pipefail`, `yaml_val` pattern, shellcheck-clean. Satisfies FR1–FR3, NFR2, AC1–AC3.

- [x] `T2` — Create `specclaw-browser-lock` helper
  - Files: `plugins/specclaw/bin/specclaw-browser-lock`
  - Estimate: large
  - Kind: impl
  - Notes: Subcommands `acquire|release <slot>|status`. N = `verify.playwright.max_browsers` (def 2). Slots = dirs `<specclaw_dir>/.locks/playwright/slot-<i>/` with a `pid` file; atomic claim via `mkdir`. `acquire` reclaims dead-PID slots (`kill -0`) before declaring full, polls with a bounded timeout, fail-open + stderr warn on timeout/unwritable dir. Satisfies FR5–FR7, NFR2–NFR3, AC4–AC6.

- [x] `T3` — Add config keys to template
  - Files: `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Kind: config
  - Notes: Under `build:` add `memory:` sub-block (`min_free_mb: 1024`, `per_agent_mb: 1024`) with comments; add/extend `verify:` with `playwright:\n    max_browsers: 2`. Document each. Satisfies FR9, AC8.

### Wave 2 — Wiring & tests

- [x] `T4` — Wire helpers into SKILL & guardrail docs
  - Files: `plugins/specclaw/skills/build/SKILL.md`, `plugins/specclaw/references/agent-guardrails.md`, `plugins/specclaw/skills/verify/SKILL.md`
  - Estimate: medium
  - Kind: docs
  - Depends: T1, T2, T3
  - Notes: build SKILL Step 3c — call `specclaw-parallel-budget` at wave start, use output as concurrency ceiling (FR4). Add guardrail rule: bracket Playwright launches with `specclaw-browser-lock acquire`/`release` (FR8). Reference the wrap in verify SKILL only if that skill actually describes browser launches — otherwise drop the verify edit and rely on guardrails (per design note). Satisfies FR4, FR8, AC9.

- [x] `T5` — Regression tests for both helpers
  - Files: `plugins/specclaw/tests/` (new test script + wire into `run-parser-tests.sh` or the suite runner)
  - Estimate: medium
  - Kind: test
  - Depends: T1, T2
  - Notes: Fixture-driven meminfo for `specclaw-parallel-budget` (AC1 → 1, AC2 → 3, AC3 clamp ≥1). browser-lock: acquire/release/status round-trip, full-pool block-then-timeout, dead-PID reclaim (AC4–AC6). Ensure shellcheck covers the two new scripts (AC7/NFR1). Satisfies AC1–AC7.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Kind: docs | test | config | refactor | impl | migration   (optional)
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
