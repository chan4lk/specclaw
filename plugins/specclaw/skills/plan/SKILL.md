---
description: Generate spec, design, and ordered task list for an approved proposal. Reads proposal.md, analyzes the codebase, then writes spec.md, design.md, and tasks.md. Run after /specclaw:propose has been approved, before /specclaw:build.
---

# specclaw plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn an approved proposal into an executable plan.

1. **Validate:** run `specclaw-validate-change .specclaw <change> plan`. If it fails, report missing prerequisites and stop.
2. Read `.specclaw/changes/<change>/proposal.md`.
3. Analyze the existing codebase (file structure, patterns, dependencies relevant to the change).
4. Generate three files in `.specclaw/changes/<change>/`:
   - `spec.md` — functional requirements, non-functional requirements, acceptance criteria, edge cases. Use `$CLAUDE_PLUGIN_ROOT/templates/spec.md` as a starting template.
   - `design.md` — technical approach, architecture, file changes map, key decisions, risks. Template: `$CLAUDE_PLUGIN_ROOT/templates/design.md`.
   - `tasks.md` — ordered tasks grouped into waves with dependencies. Template: `$CLAUDE_PLUGIN_ROOT/templates/tasks.md`.
5. Present a plan summary to the user (counts of FRs, ACs, tasks, waves).
6. Update status: `specclaw-update-status .specclaw`.
7. **GitHub sync** (if enabled): `specclaw-gh-sync update .specclaw <change>` to attach the task checklist to the GitHub Issue.
8. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the rendered task checklist.

## Planner guardrails

When generating `tasks.md`, apply the same rules `/specclaw:build` injects into coding agents — see `references/agent-guardrails.md`. In particular: **Rule 1 (Think Before Coding)** — state assumptions explicitly in the spec/design and ask if anything is unclear, rather than picking silently between interpretations. **Rule 2 (Simplicity First)** — no speculative tasks, no over-decomposition; if three tasks could be one, make it one.
