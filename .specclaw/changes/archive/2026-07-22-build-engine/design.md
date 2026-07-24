# Design: Build Engine — Core Orchestration

**Change:** build-engine
**Created:** 2026-03-28

## Technical Approach

The build engine is a **hybrid shell + agent orchestration** system. Shell scripts handle deterministic work (parsing, git, status updates), while the OpenClaw agent handles non-deterministic work (context preparation, agent spawning, result interpretation).

The main entry point is `scripts/build.sh`, which the agent calls to set up git, parse tasks, and update statuses. The agent then drives the wave execution loop — spawning coding agents, waiting for results, and calling status update scripts between waves.

This split keeps scripts testable and the agent's job focused on what it does best: reading code context, building prompts, and coordinating async work.

## Architecture

```
User: "specclaw build <change>"
  │
  ▼
Agent (SKILL.md instructions)
  │
  ├── 1. scripts/build.sh setup <change>
  │     ├── Parse config.yaml
  │     ├── Git branch setup
  │     └── Return config JSON
  │
  ├── 2. scripts/parse-tasks.sh <tasks.md>
  │     └── Return tasks JSON
  │
  ├── 3. For each wave (agent loop):
  │     ├── Filter pending tasks for this wave
  │     ├── Build context per task (agent reads files, preps prompts)
  │     ├── sessions_spawn per task (respecting parallel limit)
  │     ├── sessions_yield (wait for batch)
  │     ├── scripts/update-task-status.sh per completed task
  │     └── scripts/build.sh commit <change> <task_id> <files>
  │
  ├── 4. scripts/build.sh finalize <change>
  │     ├── Run test/lint/build commands
  │     ├── Merge branch (if branch-per-change)
  │     └── Return summary
  │
  └── 5. scripts/update-status.sh <specclaw_dir>
        └── Regenerate STATUS.md dashboard
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `skill/scripts/build.sh` | **Create** | Main build orchestrator: setup, commit, finalize subcommands |
| `skill/scripts/parse-tasks.sh` | **Modify** | Fix edge cases, add `--wave` filter, validate JSON output |
| `skill/scripts/update-task-status.sh` | **Modify** | Add batch mode, timestamp logging |
| `skill/scripts/update-status.sh` | **Modify** | Add build phase detection, time tracking |
| `skill/scripts/build-context.sh` | **Create** | Prepare context payload for a single task (read files, format prompt) |
| `skill/references/build-engine.md` | **Modify** | Update with actual implementation details, remove pseudocode |
| `skill/SKILL.md` | **Modify** | Add detailed `specclaw build` execution steps referencing new scripts |
| `skill/templates/status.md` | **Modify** | Add agent run tracking fields |

## Data Model Changes

### Task JSON Schema (output of parse-tasks.sh)

```json
[
  {
    "id": "T1",
    "title": "Create theme context provider",
    "status": "pending",
    "wave": 1,
    "files": ["src/contexts/ThemeContext.tsx"],
    "depends": [],
    "estimate": "small",
    "notes": ""
  }
]
```

### Build State (transient, in status.md)

```markdown
## Agent Runs
| Task | Agent Label | Runtime | Model | Status | Started | Duration |
|------|-------------|---------|-------|--------|---------|----------|
| T1   | specclaw-build-engine-T1 | acp | codex | complete | 12:01 | 45s |
```

## API Changes

No external APIs. The "API" is the script interface:

- `build.sh setup <specclaw_dir> <change_name>` → JSON config + branch info
- `build.sh commit <specclaw_dir> <change_name> <task_id> "<title>" <files...>` → git add + commit
- `build.sh finalize <specclaw_dir> <change_name>` → test + merge + summary
- `parse-tasks.sh <tasks.md> [--wave N] [--status pending|failed]` → filtered JSON
- `build-context.sh <specclaw_dir> <change_name> <task_id>` → context payload string
- `update-task-status.sh <tasks.md> <task_id> <status>` → update marker (existing)

## Key Decisions

1. **Shell scripts for deterministic work, agent for orchestration** — Scripts are testable, cacheable, and don't burn tokens. The agent focuses on context building and coordination.

2. **JSON as the interchange format** — Tasks parsed to JSON, config read as YAML → JSON. Everything piped through `jq` for filtering. Reliable and standard.

3. **Wave-based with batching, not pure DAG** — Simpler than a full dependency graph. Waves are explicit in `tasks.md`, making them human-readable and predictable.

4. **build-context.sh reads files but agent can override** — The script builds a default context payload, but the agent can read additional files or trim sections when needed. Script provides the 80%, agent handles the 20%.

5. **Status.md as the observability layer** — Every agent spawn, completion, and failure logged with timestamps. Makes debugging and resumability straightforward.

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| awk parser fails on unusual markdown | Tasks not parsed | Add validation step, test with varied inputs |
| Agent spawned with too much context | Token limit exceeded | build-context.sh caps file content at 500 lines per file |
| Git merge conflicts on finalize | Build stalls | Detect conflicts, report to user, don't auto-resolve |
| Multiple builds running simultaneously | Race condition on tasks.md | Check for `[~]` in_progress tasks at startup, warn if found |
