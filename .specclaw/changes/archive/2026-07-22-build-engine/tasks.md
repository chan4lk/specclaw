# Tasks: Build Engine — Core Orchestration

**Change:** build-engine
**Created:** 2026-03-28
**Total Tasks:** 6

## Summary

Build the core orchestration engine in 3 waves: foundation scripts (parseable, testable), the main build orchestrator + context builder, and finally the SKILL.md integration + reference doc updates.

## Tasks

### Wave 1 — Foundation scripts (independent, testable)

- [x] `T1` — Harden parse-tasks.sh: edge cases, --wave/--status filters, JSON validation
  - Files: skill/scripts/parse-tasks.sh
  - Estimate: small
  - Notes: Add getopts for --wave N and --status pending|failed filters. Handle empty files, malformed entries, tasks at EOF. Validate output with jq --exit-status. Add usage help.

- [x] `T2` — Enhance update-task-status.sh with batch mode and timestamps
  - Files: skill/scripts/update-task-status.sh
  - Estimate: small
  - Notes: Add batch mode accepting multiple task_id:status pairs. Log timestamp of each change. Add --quiet flag for scripted use. Preserve file formatting.

### Wave 2 — Build orchestrator and context builder

- [x] `T3` — Create build.sh with setup/commit/finalize subcommands
  - Files: skill/scripts/build.sh
  - Depends: T1, T2
  - Estimate: medium
  - Notes: setup: read config.yaml, create git branch if branch-per-change, output config JSON. commit: git add listed files + commit with specclaw prefix. finalize: run test/lint/build commands, merge branch, output summary JSON. Handle missing config fields with defaults.

- [x] `T4` — Create build-context.sh for per-task context payload construction
  - Files: skill/scripts/build-context.sh
  - Depends: T1
  - Estimate: medium
  - Notes: Read spec.md, design.md, task details from tasks JSON. Read existing file contents (cap 500 lines each). Format using Build Agent template from agent-prompts.md. Output complete context string to stdout. Handle "new file" case.

### Wave 3 — Integration and documentation

- [x] `T5` — Update SKILL.md with detailed specclaw build execution flow
  - Files: skill/SKILL.md
  - Depends: T3, T4
  - Estimate: medium
  - Notes: Add step-by-step agent instructions for the build command. Reference build.sh, parse-tasks.sh, build-context.sh. Document wave loop with sessions_spawn + sessions_yield. Include retry logic for failed tasks. Add notification message templates.

- [x] `T6` — Update build-engine.md reference with actual implementation details
  - Files: skill/references/build-engine.md
  - Depends: T3, T4
  - Estimate: small
  - Notes: Replace pseudocode with real script calls and actual JSON schemas. Document the setup→waves→finalize flow. Add troubleshooting section. Keep it as developer reference (SKILL.md is the agent-facing doc).

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
