# Proposal: On-the-fly (dynamically synthesized) build subagents

**Created:** 2026-07-19
**Status:** 🟡 Draft

## Problem

The build phase (`/specclaw:build`, Step 3c) spawns one **homogeneous generic coding agent** per task — the catch-all `claude` agent, `models.coding` model, full `*` tools, one broad system prompt. Every task, whatever its nature, runs through the identical undifferentiated agent.

Costs:
- **No specialization.** A test task, a docs task, a schema migration, and a refactor share one generic prompt. Quality rides entirely on the per-task context payload; the agent gets no role framing.
- **Over-broad tool grants.** Every agent gets `*` even when the task only needs Read/Edit. Wider blast radius, more scope-creep risk.
- **Model mismatch.** Trivial rename and cross-module refactor use the same tier — no cheap-fast routing for easy tasks, no stronger model for hard ones.
- **Contrast with the lifecycle.** Plan and verify delegate to purpose-built subagents (`spec-author`, `code-reviewer`) with focused prompts and minimal tools. Build — the longest phase — still uses the generic agent.

Fixed pre-defined agent *types* only partly fix this: a curated set (`test-writer`, `docs-writer`, …) can never anticipate every task a proposal produces. We want the agent **tailored to the actual task**, drawn from the proposal/spec — not slotted into the nearest static bucket.

## Proposed Solution

**Synthesize a bespoke subagent per task on the fly** from the change's proposal + spec + task metadata, instead of routing to fixed agent types.

For each build task, build **generates an ephemeral agent definition** — a focused system prompt (role, the task's slice of spec/design, constraints), a minimal tool set, and a model tier — then dispatches the task to a `general-purpose` agent carrying that synthesized prompt. The agent is composed for *this* task; nothing is pre-registered.

### Mechanism (Claude Code reality check)
Claude Code offers two ways to run a non-generic agent, and they bound this design:
- **Static subagents** — `.md` files in `agents/`, fixed `subagent_type`. Reusable but must be authored ahead of time; can't be tailored to an unforeseen task. (This is what a "defined agent types" approach would use.)
- **Runtime-synthesized agents** — the main agent (driven by the skill's markdown) builds a custom system-prompt payload at build time and spawns a `general-purpose`/generic agent with it. **No file, no pre-registration** — genuinely per-task. This is the portable primitive available to a *plugin* skill, so it's the one this proposal targets.

("Dynamic workflow" in Claude terms = multi-agent orchestration that fans out agents with inline-generated prompts. The SDK lets you define agents dynamically in code; a plugin skill can't assume that runtime, so we express the same idea as "skill instructs main agent to synthesize + spawn.")

### High-level approach
1. **Agent-spec synthesis (hybrid).** New helper (`specclaw-build synth-agent` or a skill step) that, given `<change>` + `<task>`, emits a JSON agent spec: `{ role, system_prompt, tools[], model }`. **Hybrid driver:** a deterministic template scaffolds the spec (role skeleton, guardrails, tool/model defaults from task kind) and a short LLM fill tailors the role + system prompt to the task's slice of proposal/spec/design. Template gives cheap/predictable structure; the LLM pass adds task-specific framing.
2. **Prompt template.** A synthesis template (in `plugins/specclaw/templates/`) that turns those inputs into a focused role + the task's slice of spec/design + guardrails (stay in declared files, satisfy these acceptance criteria).
3. **Tool minimization.** Derive a **minimal tool set** per task (docs → Read/Write; test → Read/Write/Bash; impl → full). No `*` grant unless the task needs it.
3b. **Cost-aware model routing (Claude-only ladder).** Pick the **cheapest Claude model that fits** the task, not a flat tier. Concrete ladder (latest Claude ids only — no OpenAI):
   - trivial / docs / rename → `claude-haiku-4-5`
   - standard impl → `claude-sonnet-5` (this becomes the new `models.coding` default, replacing today's `openai/gpt-5.1-codex`)
   - complex / cross-module → `claude-opus-4-8`
   - **highly complex only** → `claude-fable-5`, used for a **small fraction** of tasks and gated by the spend ceiling (a fraction of Fable usage is acceptable for the hardest tasks).

   Also refresh the other model routes to latest Claude while here: `models.planning` → `claude-opus-4-8`, `models.review` → `claude-sonnet-5`. A config ceiling caps spend; synthesis never exceeds it.
4. **Dispatch.** Step 3c spawns the generic agent with the synthesized system prompt as its instruction, at the derived model, with the minimized tools.
5. **Cache + provenance.** **Persist** each synthesized spec under `.specclaw/changes/<change>/agents/<TASK_ID>.json` for audit/replay, and log the synthesized role/model per task into status.md's Agent Runs table (already has Agent/Model columns). Re-runs reuse the cached spec unless the task changed.
6. **Config + fallback.** `build.dynamic_agents` toggle in config.yaml. Default **off** → current single generic-agent behavior. On failure to synthesize, fall back to today's generic coder (never blocks a build).

## Scope

### In Scope
- Per-task **hybrid** agent-spec synthesis (deterministic template scaffold + short LLM fill) from proposal/spec/design/task.
- Synthesis prompt template + **minimal** tool derivation.
- **Cost-aware model routing** — cheapest Claude model that fits, by kind + estimate, under a config spend ceiling.
- **Update `models` block in `config.yaml`** to Claude-only latest ids (coding → sonnet-5, planning → opus-4-8, review → sonnet-5) + the build ladder incl. fable-5 for the highly-complex fraction.
- Dispatch in `build/SKILL.md` Step 3c using the synthesized prompt.
- **Caching** synthesized specs under `.specclaw/changes/<change>/agents/<TASK_ID>.json` for audit/replay.
- `build.dynamic_agents` config toggle; default-off preserves current behavior.
- Provenance logging into status.md Agent Runs.

### Out of Scope
- Writing new persistent `agents/*.md` subagent-type files at runtime (specs are cached as JSON data, not registered as Claude Code subagent types — avoids agent-discovery/reload issues).
- Changing `spec-author` / `code-reviewer` (plan/verify unchanged).
- Changing `parallel_tasks` concurrency semantics.
- A hard dependency on any SDK-only or harness-only "workflow" API (must work as a plain plugin skill).

## Impact

- **Files affected:** ~4–6 (estimated) — `build/SKILL.md`, `config.yaml` template, a synthesis template, possibly a `specclaw-build synth-agent` helper, optional `plan/SKILL.md` for task hints.
- **Complexity:** medium
- **Risk:** low–medium — default-off + generic fallback keeps current builds identical; main risk is synthesized-prompt quality, mitigated by falling back on failure.

## Decisions (resolved)

1. **Synthesis driver → hybrid.** Deterministic template scaffold + short LLM fill. Predictable structure, task-specific framing.
2. **Persistence → cache.** Synthesized specs saved under `.specclaw/changes/<change>/agents/<TASK_ID>.json` for audit/replay; re-runs reuse unless the task changed.
3. **Tools → minimize.** Derive the smallest tool set per task; no blanket `*`.
4. **Model routing → cost-aware, Claude-only.** Cheapest fitting Claude model by kind + estimate, under a config spend ceiling. Ladder: haiku-4-5 → sonnet-5 → opus-4-8 → fable-5 (fable for the highly-complex fraction only). Replaces `models.coding: openai/gpt-5.1-codex`; also bumps planning/review to latest Claude.

## Open Questions

1. **Portability line** — commit to the plugin-skill "synthesize + spawn generic" mechanism, or optionally light up a true orchestration/`Workflow` path when the running harness provides one?
2. **Guardrails** — how hard do we constrain synthesized agents to declared files / acceptance criteria to keep scope-creep no worse than today?
3. **Cost ceiling shape** — per-task cap, per-build budget, or both? And which model list defines the cheap→strong ladder in config?

---

**To proceed:** Review this proposal and approve to begin planning.
