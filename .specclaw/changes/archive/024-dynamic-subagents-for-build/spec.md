# Spec: On-the-fly (dynamically synthesized) build subagents

**Change:** dynamic-subagents-for-build
**Created:** 2026-07-19
**Status:** 🟡 Draft

## Overview

`/specclaw:build` Step 3c currently spawns one homogeneous generic coding agent per task (`models.coding`, full `*` tools, one broad prompt). This change lets build **synthesize a bespoke agent per task** from the change's proposal/spec/design + task metadata: a focused system prompt, a minimized tool set, and a cost-aware Claude model. The synthesized spec is cached for audit/replay. Behavior is **opt-in** (`build.dynamic_agents.enabled`, default off) with a generic-agent fallback so existing builds are byte-identical until enabled.

Synthesis is **hybrid**: a deterministic helper (`specclaw-build synth-agent`) produces a scaffold (kind classification, tool set, model tier, guardrail skeleton); the build skill's main agent enriches the `system_prompt` with the task's slice of spec/design (the LLM-fill step) and persists the final spec.

## Requirements

### Functional Requirements

- **FR1 — Kind classification.** Given a task, derive a `kind` (`docs`, `test`, `config`, `refactor`, `impl`, `migration`) from an explicit `kind:` task field when present, else heuristically from title + declared files + estimate. Explicit overrides heuristic.
- **FR2 — Tool minimization.** Derive a minimal tool set from `kind` (e.g. `docs → [Read, Write]`; `test → [Read, Write, Bash]`; `impl → [Read, Write, Edit, Bash, Grep, Glob]`). No blanket `*` unless the kind requires it.
- **FR3 — Cost-aware model routing (Claude-only).** Map `kind` + `estimate` to the cheapest fitting Claude model on the ladder: `claude-haiku-4-5` → `claude-sonnet-5` → `claude-opus-4-8` → `claude-fable-5`. `claude-fable-5` is selected **only** for tasks explicitly marked highly complex, and only while under the configured Fable fraction cap. A configured `max_model` ceiling is never exceeded.
- **FR4 — Hybrid synthesis.** `specclaw-build synth-agent <dir> <change> <task>` emits a deterministic JSON scaffold `{ kind, role, tools[], model, system_prompt }`. The build skill enriches `system_prompt` with the task's spec/design slice + guardrails before dispatch.
- **FR5 — Guardrails in synthesized prompt.** Every synthesized `system_prompt` embeds the existing build agent guardrails (stay within declared files, satisfy the task's acceptance criteria, simplicity-first) so scope-creep risk is no worse than today's generic agent.
- **FR6 — Cache + provenance.** The final synthesized spec is written to `.specclaw/changes/<change>/agents/<TASK_ID>.json`. Re-runs reuse the cached spec unless the task's title/files/estimate/kind changed. The chosen role + model are logged into `status.md`'s Agent Runs table.
- **FR7 — Dispatch.** When enabled, Step 3c spawns a generic (`general-purpose`) agent carrying the synthesized `system_prompt` + the existing `specclaw-build-context` payload, restricted to the synthesized tools, at the synthesized model.
- **FR8 — Opt-in + fallback.** `build.dynamic_agents.enabled` gates the whole feature (default `false`). If synthesis fails for a task, build falls back to the current generic coder for that task and continues — never blocks a build.
- **FR9 — Config: models block.** Update the `models` block (both the project's live `.specclaw/config.yaml` and the `plugins/specclaw/templates/config.yaml` init template) to Claude-only latest ids: `planning: claude-opus-4-8`, `coding: claude-sonnet-5`, `review: claude-sonnet-5`. Remove `openai/gpt-5.1-codex`.
- **FR10 — Config: dynamic_agents block.** Add a `build.dynamic_agents` config block (ladder, `max_model`, `fable_max_fraction`, `cache`, `enabled`) to both config files, defaulting to disabled with the ladder pre-filled.

### Non-Functional Requirements

- **NFR1 — Backward compatibility.** With `enabled: false`, build output and agent dispatch are unchanged from today.
- **NFR2 — No new hard dependency.** Must work as a plain plugin skill — no reliance on any SDK-only or harness-only orchestration/`Workflow` API. Bash + jq only for helpers.
- **NFR3 — Deterministic scaffold.** `synth-agent` scaffold output is deterministic for a given task (no randomness), so caching + replay are stable.
- **NFR4 — Portable model ids.** Model ids read from config, not hardcoded in the helper, so future model bumps are config-only.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — `specclaw-build synth-agent .specclaw dynamic-subagents-for-build <task>` emits valid JSON with keys `kind, role, tools, model, system_prompt`; `jq` parses it.
- **AC2** — A `docs` task yields `tools ⊆ [Read, Write]` and model `claude-haiku-4-5`; an `impl`/`large` task yields the coding tool set and `claude-opus-4-8`; no task yields `claude-fable-5` unless explicitly marked highly complex.
- **AC3** — With `build.dynamic_agents.enabled: false`, a build run dispatches exactly as before (generic agent, `models.coding`) — no synthesis, no `agents/` dir written.
- **AC4** — With `enabled: true`, running a build writes one `.specclaw/changes/<change>/agents/<TASK_ID>.json` per dispatched task and records role+model in `status.md` Agent Runs.
- **AC5** — Forcing a synthesis failure for a task falls back to the generic coder and the build completes (task not marked failed for that reason).
- **AC6** — `grep -rn "gpt-5.1-codex\|sonnet-4-6\|sonnet 4.6" .specclaw/config.yaml plugins/specclaw/templates/config.yaml` returns nothing; `models.coding` is `claude-sonnet-5`.
- **AC7** — Every synthesized `system_prompt` contains the declared-files fence and the task's acceptance-criteria reference (guardrail text present).
- **AC8** — Re-running synthesis for an unchanged task returns the cached spec (no rewrite); changing a task's files invalidates the cache and regenerates.
- **AC9** — `specclaw-parse-tasks` still parses tasks lacking a `kind:` field (backward compatible) and surfaces `kind` when present.

## Edge Cases

- Task with no `kind:` and ambiguous title/files → heuristic defaults to `impl` (safe: full-ish tools, coding model).
- `fable_max_fraction` already reached in a build → next highly-complex task falls back to `claude-opus-4-8`, logged as a downgrade.
- `max_model` set below a task's routed tier → clamp down to `max_model`, log the clamp.
- Missing/empty `agents/` cache dir → created on first write.
- Cached spec present but `synth-agent` schema changed (version bump) → treat as stale, regenerate.
- Worktree strategy active → `agents/` cache lives under the main `.specclaw/changes/<change>/`, not the worktree, so it survives merge.

## Dependencies

- Existing helpers: `specclaw-build` (add `synth-agent` subcommand), `specclaw-build-context`, `specclaw-parse-tasks` (add optional `kind`), `specclaw-update-status`.
- `jq` (already a soft dependency across specclaw bins).
- Build skill markdown (`plugins/specclaw/skills/build/SKILL.md`).

## Notes

- Portability question resolved: commit to the plugin-skill "synthesize + spawn generic" mechanism; no `Workflow`/SDK dependency (NFR2).
- Guardrail question resolved: reuse existing `references/agent-guardrails.md` text inside the synthesized prompt (FR5).
- Ceiling question resolved: per-build `max_model` ceiling + `fable_max_fraction` share cap; ladder defined in config (FR3/FR10).
- The "LLM fill" half of hybrid synthesis is performed by the build skill's main agent, not a bash call — helpers stay deterministic (NFR3).
