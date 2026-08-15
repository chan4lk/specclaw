# Verify Report: memory-aware-parallelism

**Date:** 2026-07-24
**Change:** memory-aware-parallelism

## Verdict: PASS

All 9 acceptance criteria verified independently by running the helpers directly (not
trusting prior claims). The regression suite passes 16/16, both bin scripts are
shellcheck-clean, the three config keys exist at the correct paths, and the SKILL /
guardrail docs wire the helpers in at the specified points.

## Acceptance Criteria

| AC | Status | Evidence |
|----|--------|----------|
| AC1 | ✅ | Fixture `MemAvailable: 2560000 kB` (=2500MB), config `parallel_tasks=3, min_free_mb=1024, per_agent_mb=1024`. `SPECCLAW_MEMINFO_PATH=<fixture> specclaw-parallel-budget <dir>` → `1` (floor((2500−1024)/1024)=1). |
| AC2 | ✅ | Real repo `specclaw-parallel-budget .specclaw` (no `build.memory` block) → `3`. Also confirmed against a config with no memory block + a tight fixture → still `3` (opt-in, no gating). |
| AC3 | ✅ | Config `min_free_mb=999999` against the 2500MB fixture → `1` (never `0`/negative; clamp holds under extreme pressure). |
| AC4 | ✅ | `max_browsers=2` pool: fresh `status` → `0/2`; two live-PID slots held → `status` `2/2`; over-cap `SPECCLAW_BROWSER_LOCK_TIMEOUT=1 ... acquire` → prints `none`, exit 0, warns "timed out" to stderr, returns in 1s (bounded, fail-open per NFR3). |
| AC5 | ✅ | slot-1 holder killed (dead PID); next `acquire` (timeout 30) reclaims and returns `slot-1` in 0s — fast, well before timeout (FR7 PID-liveness reclaim). |
| AC6 | ✅ | `release slot-1` frees it; `status` reflects held/max accurately (`1/2` with slot-2 still live). Suite case 6b additionally confirms `0/2` after release and re-acquire reusing `slot-1`. |
| AC7 | ✅ | `npx --yes shellcheck@latest` on both `specclaw-parallel-budget` and `specclaw-browser-lock` → exit 0, no output (clean). |
| AC8 | ✅ | `templates/config.yaml`: `build.memory.min_free_mb` (L56) + `build.memory.per_agent_mb` (L57) under `build:` (L49); `verify.playwright.max_browsers` (L77) under `verify:` (L75). All with defaults + inline comments. |
| AC9 | ✅ | `skills/build/SKILL.md` Step 3b'/3c calls `specclaw-parallel-budget .specclaw` as the per-wave concurrency ceiling (≤ `parallel_tasks`). `references/agent-guardrails.md` (L94–96) instructs `specclaw-browser-lock acquire` before launch / `release <slot>` after. Build SKILL intentionally has **no** browser section (grep for browser/playwright/browser-lock returns nothing) — browser cap belongs to verify/run guardrails by design; acceptable. |

## Test & Lint Confirmation

- **Test suite:** `bash plugins/specclaw/tests/run-memory-parallelism-tests.sh` → **16 passed, 0 failed**, exit 0. Covers AC1–AC3, the `per_agent_mb=0` divide-by-zero edge case, and AC4–AC6 browser-lock lifecycle.
- **ShellCheck (NFR1 / AC7):** both bin scripts clean (exit 0).

## Gaps

None. No divergence from spec found. Edge cases in the spec (per_agent_mb=0, extreme
pressure clamp, dead-PID reclaim, over-cap timeout fail-open) are all exercised and pass.
