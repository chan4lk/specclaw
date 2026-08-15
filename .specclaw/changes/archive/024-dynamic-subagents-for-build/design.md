# Design: On-the-fly (dynamically synthesized) build subagents

**Change:** dynamic-subagents-for-build
**Created:** 2026-07-19

## Technical Approach

Add a **hybrid, opt-in synthesis layer** to the build wave loop. Split of labor:

- **Deterministic half (bash, `specclaw-build synth-agent`):** classify task `kind`, derive minimal `tools`, route to a cost-aware Claude `model`, and assemble a scaffold `system_prompt` (role skeleton + guardrail block). Pure functions of the task metadata + config → deterministic, cacheable (NFR3).
- **LLM-fill half (build skill main agent):** read the scaffold + the task's spec/design slice, enrich `system_prompt` with task-specific framing, persist the final spec JSON to the cache, then dispatch a `general-purpose` agent with it.

Everything is gated by `build.dynamic_agents.enabled` (default `false`). Off → the existing Step 3c path runs untouched (NFR1). Synthesis failure for any task → fall back to the generic coder for that task (FR8).

Model ids live in config, never hardcoded in the helper (NFR4).

## Architecture

```
Wave loop (build/SKILL.md Step 3c), per task:
  if dynamic_agents.enabled:
     scaffold = `specclaw-build synth-agent .specclaw <change> <TASK_ID>`   # JSON {kind,role,tools,model,system_prompt}
     (cache hit? reuse agents/<TASK_ID>.json : )
     final = main-agent enriches scaffold.system_prompt with spec/design slice
     write .specclaw/changes/<change>/agents/<TASK_ID>.json  (final)
     payload = `specclaw-build-context .specclaw <change> <TASK_ID>`         # unchanged
     spawn general-purpose agent:
        system_prompt = final.system_prompt
        prompt        = payload
        tools         = final.tools
        model         = final.model
     log role+model → status.md Agent Runs
  else:
     <existing behavior: generic agent, models.coding, payload>
```

`synth-agent` internals (deterministic):
1. Parse the task via `specclaw-parse-tasks` (now carrying optional `kind`).
2. **Classify:** explicit `kind:` wins; else heuristic — title/keywords + file extensions + estimate → one of `docs|test|config|refactor|impl|migration`. Unknown → `impl`.
3. **Tools:** lookup table `kind → tools[]`.
4. **Model:** `(kind, estimate) → tier`, then `tier → config ladder id`. Clamp to `max_model`. `fable` tier requires explicit highly-complex mark AND under `fable_max_fraction` (share tracked via count of existing `agents/*.json` at `claude-fable-5`); else downgrade to `opus`.
5. **Scaffold prompt:** role line + guardrail block (from `references/agent-guardrails.md`) + placeholder marker for the LLM-fill slice.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-build` | modify | Add `synth-agent` subcommand: classify kind, derive tools/model, emit scaffold JSON; cache-aware read of `agents/<TASK_ID>.json`. |
| `plugins/specclaw/bin/specclaw-parse-tasks` | modify | Parse optional `- Kind: <k>` detail line; add `"kind"` to emitted JSON (empty when absent — backward compatible). |
| `plugins/specclaw/skills/build/SKILL.md` | modify | Step 3c: branch on `dynamic_agents.enabled`; synth → enrich → cache → dispatch generic agent with synthesized prompt/tools/model; fallback on failure; log provenance. |
| `plugins/specclaw/templates/config.yaml` | modify | Claude-only `models` block; new `build.dynamic_agents` block (enabled:false, ladder, max_model, fable_max_fraction, cache). |
| `.specclaw/config.yaml` | modify | Same edits applied to this project's live config. |
| `plugins/specclaw/templates/tasks.md` | modify | Document optional `- Kind:` task field in the task format legend. |
| `plugins/specclaw/skills/plan/SKILL.md` | modify | Instruct planner to tag each task with a `Kind:` hint (optional, non-breaking). |
| `.specclaw/changes/dynamic-subagents-for-build/agents/` | create (runtime) | Cache dir for synthesized specs (created by build, gitignored path under change). |

## Data Model Changes

**Synthesized agent spec** (`agents/<TASK_ID>.json`):
```json
{
  "task": "T3",
  "kind": "impl",
  "role": "Implementation agent for T3 — <title>",
  "tools": ["Read", "Write", "Edit", "Bash", "Grep", "Glob"],
  "model": "anthropic/claude-sonnet-5",
  "system_prompt": "<role + guardrails + task spec/design slice>",
  "schema_version": 1
}
```

**Config additions:**
```yaml
models:
  planning: "anthropic/claude-opus-4-8"
  coding:   "anthropic/claude-sonnet-5"
  review:   "anthropic/claude-sonnet-5"

build:
  dynamic_agents:
    enabled: false
    ladder:
      trivial:  "anthropic/claude-haiku-4-5"
      standard: "anthropic/claude-sonnet-5"
      complex:  "anthropic/claude-opus-4-8"
      extreme:  "anthropic/claude-fable-5"
    max_model: "anthropic/claude-opus-4-8"   # ceiling; extreme requires explicit highly-complex mark
    fable_max_fraction: 0.2                    # cap Fable share of tasks per build
    cache: true
```

**Classification tables (in helper):**
- Tools: `docs→[Read,Write]`, `config→[Read,Edit]`, `test→[Read,Write,Bash]`, `refactor→[Read,Edit,Grep,Glob]`, `impl→[Read,Write,Edit,Bash,Grep,Glob]`, `migration→[Read,Write,Edit,Bash]`.
- Tier: `docs/config + small → trivial`; `test/impl/refactor + small|medium → standard`; `* + large → complex`; explicit highly-complex mark → `extreme`.

## API Changes

New CLI surface: `specclaw-build synth-agent <specclaw_dir> <change> <task_id>` → JSON to stdout (scaffold or cached final). No breaking changes to existing subcommands. `specclaw-parse-tasks` JSON gains a `kind` field (additive).

## Key Decisions

1. **Ephemeral JSON specs, not `agents/*.md` subagent types.** Synthesized specs are data spawned via the generic agent — avoids Claude Code subagent-discovery/reload friction and keeps the feature portable (NFR2).
2. **Bash stays deterministic; LLM-fill in the skill.** A bash helper can't call a model, so the "hybrid" LLM enrichment is done by the build skill's main agent. Helper = classification + routing + scaffold only (NFR3).
3. **Config-driven ladder + ceiling.** Model ids and caps live in config so bumps are config-only and Fable stays cost-bounded (FR3/FR10, NFR4).
4. **Opt-in with per-task fallback.** Default-off + graceful fallback guarantees no regression to current builds (NFR1, FR8).
5. **Reuse existing context + guardrails.** `specclaw-build-context` payload and `references/agent-guardrails.md` are reused verbatim — synthesis only adds a specialized system prompt on top.

## Risks & Mitigations

- **Risk: synthesized prompt quality varies → worse output than generic.** Mitigation: guardrails embedded (FR5), fallback on failure (FR8), default-off until validated.
- **Risk: Fable cost blowout.** Mitigation: `extreme` requires explicit mark + `fable_max_fraction` cap + `max_model` ceiling defaulting to opus (Fable off unless raised).
- **Risk: cache staleness after schema changes.** Mitigation: `schema_version` in spec; mismatched version treated as stale and regenerated.
- **Risk: model id drift (e.g. `claude-sonnet-5` exact id).** Mitigation: ids centralized in config; confirm exact ids before build. **Open: confirm `claude-sonnet-5` id form.**
- **Risk: scope creep from broader tools on `impl`.** Mitigation: `impl` still narrower than `*`; declared-files fence in prompt.
