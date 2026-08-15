# Tasks: On-the-fly (dynamically synthesized) build subagents

**Change:** dynamic-subagents-for-build
**Created:** 2026-07-19
**Total Tasks:** 7

## Summary

Add an opt-in hybrid synthesis layer to `/specclaw:build`: classify each task, derive minimal tools + a cost-aware Claude model, synthesize a bespoke agent prompt, cache it, and dispatch a generic agent with it — default-off with generic fallback. Also switch the `models` block to Claude-only latest ids.

## Tasks

### Wave 1 — Config + task-metadata groundwork

- [x] `T1` — Switch models block to Claude-only latest ids
  - Files: `.specclaw/config.yaml`, `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Kind: config
  - Notes: `planning: anthropic/claude-opus-4-8`, `coding: anthropic/claude-sonnet-5`, `review: anthropic/claude-sonnet-5`. Remove `openai/gpt-5.1-codex` and any `sonnet-4-6`. Satisfies FR9, AC6.

- [x] `T2` — Add `build.dynamic_agents` config block (default off)
  - Files: `.specclaw/config.yaml`, `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Kind: config
  - Notes: `enabled:false`, `ladder{trivial,standard,complex,extreme}`, `max_model: opus-4-8`, `fable_max_fraction:0.2`, `cache:true`. Satisfies FR10.

- [x] `T3` — Parse optional `Kind:` task field in specclaw-parse-tasks
  - Files: `plugins/specclaw/bin/specclaw-parse-tasks`
  - Estimate: small
  - Kind: impl
  - Notes: Add `next_is_detail && /^  - Kind:/` handler mirroring Estimate; add `"kind"` to emitted JSON (empty when absent — backward compatible). Satisfies FR1, AC9.

### Wave 2 — Synthesis helper

- [x] `T4` — Add `synth-agent` subcommand to specclaw-build
  - Files: `plugins/specclaw/bin/specclaw-build`
  - Estimate: large
  - Kind: impl
  - Depends: T2, T3
  - Notes: `synth-agent <dir> <change> <task>` → deterministic JSON `{task,kind,role,tools,model,system_prompt,schema_version}`. Classify (explicit kind > heuristic on title/files/estimate, unknown→impl), tool table, tier→ladder routing with `max_model` clamp + `fable_max_fraction` guard (downgrade to opus when exceeded/unmarked), scaffold prompt incl. guardrail block from `references/agent-guardrails.md`. Cache-aware read of `agents/<TASK_ID>.json` (reuse unless task changed; `schema_version` mismatch → stale). Satisfies FR1-FR6, AC1, AC2, AC7, AC8; edge cases: ambiguous→impl, ceiling clamp, fraction cap.

### Wave 3 — Build dispatch wiring

- [x] `T5` — Wire dynamic dispatch into build Step 3c
  - Files: `plugins/specclaw/skills/build/SKILL.md`
  - Estimate: medium
  - Kind: docs
  - Depends: T4
  - Notes: Branch on `build.dynamic_agents.enabled`. When on: run `synth-agent`, main-agent enriches `system_prompt` with spec/design slice (LLM-fill), persist final to `agents/<TASK_ID>.json`, spawn `general-purpose` agent with synthesized system_prompt + existing `specclaw-build-context` payload, synthesized tools + model; log role+model to status.md Agent Runs. On synthesis failure → fallback to current generic coder. When off → unchanged. Satisfies FR7, FR8, AC3, AC4, AC5.

### Wave 4 — Planner hints + docs

- [x] `T6` — Emit `Kind:` hints from planner + document task field
  - Files: `plugins/specclaw/skills/plan/SKILL.md`, `plugins/specclaw/templates/tasks.md`
  - Estimate: small
  - Kind: docs
  - Depends: T3
  - Notes: Planner tags each task with an optional `- Kind:` hint; tasks.md legend documents the field. Non-breaking (FR1). Keep concise per Simplicity-First.

- [x] `T7` — Regression + unit checks for synth-agent and parse-tasks
  - Files: `plugins/specclaw/bin/specclaw-build`, `plugins/specclaw/bin/specclaw-parse-tasks` (test invocations / any existing test harness under `plugins/specclaw/`)
  - Estimate: medium
  - Kind: test
  - Depends: T4, T5
  - Notes: Assert AC1 (valid JSON), AC2 (docs→haiku+[Read,Write]; large impl→opus; no fable unless marked), AC8 (cache reuse + invalidation), AC9 (parse-tasks backward compat). Add to existing test setup if present; else provide runnable shell assertions.

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
  - Kind: docs | test | config | refactor | impl | migration  (optional hint)
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
