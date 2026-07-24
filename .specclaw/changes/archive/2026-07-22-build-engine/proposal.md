# Proposal: Build Engine — Core Orchestration

**Created:** 2026-03-28
**Status:** 🟢 Approved

## Problem

SpecClaw's `specclaw build <change>` command is the heart of the framework, but no implementation exists yet. The `build-engine.md` reference doc describes the orchestration logic in detail, but there's no actual code that:

- Parses `tasks.md` into structured waves
- Spawns coding agents via `sessions_spawn` per task
- Tracks progress in `status.md`
- Handles parallelism, timeouts, and failures
- Integrates with git (branch-per-change or direct)
- Sends notifications on progress/completion

Without this, SpecClaw is just templates and docs — it can't actually build anything.

## Proposed Solution

Implement the build engine as a set of shell scripts and agent prompt templates that the OpenClaw agent follows to orchestrate builds. Specifically:

1. **Task parser script** (`scripts/parse-tasks.sh`) — parse `tasks.md` into structured JSON (waves, dependencies, file lists)
2. **Build orchestrator logic** (in SKILL.md + `references/build-engine.md`) — step-by-step instructions for the agent to execute waves, spawn agents, track status
3. **Context builder template** — structured prompt template for coding agents
4. **Status tracker script** (`scripts/update-task-status.sh`) — update task markers and status.md
5. **Git integration** — branch creation, per-task commits, merge on completion

## Scope

### In Scope
- Task parser (markdown → JSON)
- Wave-based parallel execution via `sessions_spawn`
- Per-task status tracking in `tasks.md` and `status.md`
- Git operations (branch, commit, merge)
- Timeout and failure handling
- Notification messages (build started, task complete, build done)
- `scripts/build.sh` as the main entry point

### Out of Scope
- Discord button-based approvals (separate proposal)
- `specclaw auto` mode (separate proposal)
- Verification engine (separate proposal)
- ClawHub packaging (separate proposal)

## Impact

- **Files affected:** ~8 (estimated)
- **Complexity:** large
- **Risk:** medium — core functionality, but well-documented in build-engine.md reference

## Open Questions

1. Should `parse-tasks.sh` output JSON or a simpler line format?
2. Should we support `runtime: "subagent"` as well as `"acp"`, or just one?
3. How do we handle the case where a coding agent modifies files outside its declared scope?

---

**To proceed:** Review this proposal and approve to begin planning.
