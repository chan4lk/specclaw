# Spec: Build Engine — Core Orchestration

**Change:** build-engine
**Created:** 2026-03-28
**Status:** 🟢 Approved

## Overview

The build engine is SpecClaw's core — it reads a planned change (spec + design + tasks), spawns coding agents per task in wave-based parallel execution, tracks progress, handles failures, and integrates with git. It transforms SpecClaw from documentation-only into an executable framework.

## Requirements

### Functional Requirements

- **FR-1:** Parse `tasks.md` into structured JSON with wave grouping, task IDs, titles, statuses, file lists, dependencies, and estimates
- **FR-2:** Execute tasks in wave order — all tasks in a wave run before the next wave starts
- **FR-3:** Spawn coding agents via `sessions_spawn` (support both `runtime: "acp"` and `runtime: "subagent"`)
- **FR-4:** Respect `config.yaml` `build.parallel_tasks` limit — batch within a wave if needed
- **FR-5:** Build context payload per task: relevant spec sections, design sections, existing file contents, task details, constraints
- **FR-6:** Track task status transitions: pending → in_progress → complete/failed
- **FR-7:** Update `tasks.md` markers and `status.md` in real-time as tasks complete
- **FR-8:** Git integration: create branch (if branch-per-change), commit per task, merge on completion
- **FR-9:** Handle task failures: mark failed, skip dependents, report to user
- **FR-10:** Handle timeouts: kill agent after `build.timeout_seconds`, mark task failed
- **FR-11:** Send notification messages: build started, task complete/failed, build summary
- **FR-12:** Support retrying failed tasks on re-run (pick up `[!]` tasks)
- **FR-13:** File-scope policy: auto-approve changes within repo, auto-approve outside if non-destructive, otherwise prompt

### Non-Functional Requirements

- **NFR-1:** Each agent gets fresh context only — no accumulated state from prior tasks
- **NFR-2:** Scripts must work on Linux (bash 5+, standard coreutils)
- **NFR-3:** JSON output must be valid and parseable by `jq`
- **NFR-4:** Build engine must be resumable — interrupted builds can continue from last incomplete wave

## Acceptance Criteria

- [ ] **AC-1:** GIVEN a valid `tasks.md` with 3 waves WHEN `parse-tasks.sh` runs THEN outputs valid JSON array with correct wave numbers, task IDs, statuses, and file lists
- [ ] **AC-2:** GIVEN a change with Wave 1 (2 tasks) and Wave 2 (1 task) WHEN `specclaw build` runs THEN Wave 1 tasks spawn in parallel, Wave 2 waits until Wave 1 completes
- [ ] **AC-3:** GIVEN `parallel_tasks: 2` and a wave with 4 tasks WHEN building THEN spawns 2 at a time in batches
- [ ] **AC-4:** GIVEN a task agent completes successfully WHEN tracked THEN `tasks.md` marker changes from `[ ]` to `[x]` and `status.md` logs the completion
- [ ] **AC-5:** GIVEN a task agent fails WHEN tracked THEN `tasks.md` marker changes to `[!]` and dependent tasks are skipped
- [ ] **AC-6:** GIVEN `git.strategy: "branch-per-change"` WHEN build starts THEN creates `specclaw/<change-name>` branch and commits per task
- [ ] **AC-7:** GIVEN a previous build left `[!]` failed tasks WHEN `specclaw build` runs again THEN retries only the failed tasks (and their dependents)
- [ ] **AC-8:** GIVEN a task with file list WHEN context is built THEN includes current content of those files (or "new file" if they don't exist)
- [ ] **AC-9:** GIVEN build completes WHEN notified THEN sends summary with pass/fail counts and duration
- [ ] **AC-10:** GIVEN `runtime` set to `"acp"` or `"subagent"` in config WHEN spawning THEN uses the correct runtime parameter

## Edge Cases

1. Empty `tasks.md` (no tasks found) — report error, don't start build
2. Task with dependencies on a failed task — skip with clear message
3. All tasks in a wave fail — stop build, report, don't proceed to next wave
4. Task file doesn't exist yet (new file) — context says "new file to create"
5. `tasks.md` has malformed task entries — parser skips with warning
6. Git branch already exists from a previous partial build — checkout existing branch
7. Agent produces output but modifies files outside declared scope — log warning (auto-approve within repo per policy)
8. Config file missing optional fields — use defaults
9. Build interrupted mid-wave — on re-run, detect in-progress tasks and reset to pending

## Dependencies

- `jq` for JSON processing (should be available on most systems)
- `git` for version control integration
- OpenClaw `sessions_spawn` / `sessions_yield` / `subagents` tools
- OpenClaw `message` tool for notifications

## Notes

- The SKILL.md agent prompt references in `references/agent-prompts.md` already define the Build Agent template — the build engine uses this to construct context payloads
- Existing `parse-tasks.sh` has a working awk parser but needs testing and edge case fixes
- `update-task-status.sh` is functional, `update-status.sh` dashboard generator works
- The build engine is primarily orchestration logic in `scripts/build.sh` + updates to SKILL.md instructions
