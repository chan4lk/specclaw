# Verify Report: dynamic-subagents-for-build

**Verdict:** PASS
**Date:** 2026-07-19
**Change:** dynamic-subagents-for-build

## Summary

All 9 acceptance criteria satisfied. Executable behavior (kind classification, tool minimization, cost-aware model routing, caching, `Kind` parsing) is covered by a 10-assertion regression suite that passes. Dispatch-time behaviors (AC3/AC4/AC5) live in the build skill's markdown — a plugin skill, not compiled code — and are verified against the documented Step 3c flow plus the helper-level behavior they drive.

## Acceptance Criteria

| AC | Verdict | Evidence |
|----|---------|----------|
| **AC1** — synth-agent emits valid JSON with required keys | ✅ PASS | Suite Case 1: keys `downgrade,kind,model,role,schema_version,sig,system_prompt,task,tier,tools`; `json.load` parses. |
| **AC2** — kind→tools + cost-aware model routing | ✅ PASS | Suite Case 2: docs/small→`haiku-4-5`+[Read,Write]; impl/large→`opus-4-8`+full tools; extreme clamped off Fable by default opus ceiling. |
| **AC3** — `enabled:false` ⇒ unchanged generic dispatch | ✅ PASS | Config default `enabled: false`; `build/SKILL.md` Step 3c documents "skip all of the above… no synthesis, no `agents/` directory" when off. No `agents/` written under default path. |
| **AC4** — `enabled:true` writes `agents/<TASK_ID>.json` + logs role/model | ✅ PASS | Helper writes `agents/<TASK_ID>.json` on generation (verified in Case 3); SKILL Step 3c documents persistence + status.md Agent Runs provenance (3 refs). |
| **AC5** — synthesis failure → generic fallback, build continues | ✅ PASS | SKILL Step 3c step 5: "if synthesis fails … fall back to the generic coder … never block the build." |
| **AC6** — no `gpt-5.1-codex`/`sonnet-4-6`; `models.coding: claude-sonnet-5` | ✅ PASS | `grep` clean on both config files; `coding: anthropic/claude-sonnet-5`, `planning: opus-4-8`, `review: sonnet-5`. |
| **AC7** — synthesized prompt carries file fence + AC reference | ✅ PASS | Suite Case 2: system_prompt contains "Scope fence" + guardrails ("Simplicity First"); `{{SPEC_DESIGN_SLICE}}` marker for AC enrichment. |
| **AC8** — cache reuse unchanged; invalidate on task change | ✅ PASS | Suite Case 3: mtime unchanged on re-run (reuse); task edit → rewrite + new `sig`. |
| **AC9** — parse-tasks surfaces `kind`, empty when absent | ✅ PASS | Suite Case 4: `docs,impl,extreme,` (last empty); backward-compatible with kind-less tasks. |

## Non-Functional

- **NFR1 backward compat** — default `enabled:false`; off-path documented as byte-identical. ✅
- **NFR2 no hard dep** — helpers are bash + awk + sed + cksum; no SDK/Workflow API. (Test suite uses python3 for asserts only, not the shipped code path.) ✅
- **NFR3 deterministic scaffold** — no randomness; stable `sig` drives cache. ✅
- **NFR4 portable ids** — model ids read from config via `da_val`, none hardcoded in the helper. ✅

## Tests

- `plugins/specclaw/tests/run-synth-agent-tests.sh` — **10 passed, 0 failed.**
- `build.test_command` is empty (no project test command configured); suites run directly.

## Notes

- Fable (`claude-fable-5`) is intentionally unreachable under the default `max_model: opus-4-8` ceiling — it activates only when an operator raises the ceiling AND a task is explicitly `Kind: extreme` AND under `fable_max_fraction`. This matches the design decision (Fable off unless raised).
- Branch is stacked on the unmerged `verify-glob-oom-fix` (PR #42); rebase onto `main` before opening this PR so the diff is clean.
