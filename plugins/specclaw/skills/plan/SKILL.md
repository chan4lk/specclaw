---
description: Generate spec, design, and ordered task list for an approved proposal. Reads proposal.md, analyzes the codebase, then writes spec.md, design.md, and tasks.md. Run after /specclaw:propose has been approved, before /specclaw:build.
---

# specclaw plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn an approved proposal into an executable plan.

## Flags

- `--author-spec` — delegate spec authoring to the `spec-author` subagent for an interactive, technique-driven dialogue (5 Whys, Jobs-to-be-Done, Inversion, Pre-mortem, MoSCoW). When this flag is present, **pause for explicit user approval of `spec.md`** before generating `design.md` and `tasks.md`. Without the flag, behavior is unchanged (single-shot generation, no dialogue) so `/specclaw:auto` remains non-interactive.

  Detect the flag as a whitespace-delimited token anywhere in ARGUMENTS (positional-agnostic), and strip it before using the rest of ARGUMENTS as `<change>`.

1. **Validate:** run `specclaw-validate-change .specclaw <change> plan`. If it fails, report missing prerequisites and stop.
2. Read `.specclaw/changes/<change>/proposal.md`.
3. Analyze the existing codebase (file structure, patterns, dependencies relevant to the change).
4. Generate three files in `.specclaw/changes/<change>/`:
   - `spec.md` — functional requirements, non-functional requirements, acceptance criteria, edge cases.
     - **If `--author-spec` is set:** invoke the `spec-author` subagent via the `Agent` tool with `subagent_type: "spec-author"` to author the spec interactively. After the agent writes the file, **STOP and require explicit user approval** (e.g. "approved", "yes", "go") before proceeding to `design.md` and `tasks.md`. Do not generate the remaining files until the user approves.
     - **Otherwise:** generate `spec.md` directly using `$CLAUDE_PLUGIN_ROOT/templates/spec.md` as a starting template (single-shot, no dialogue).
     - **If `spec.md` already exists** (e.g. authored previously via `/specclaw:author-spec`): do not overwrite it; skip the spec step and proceed to `design.md` / `tasks.md`.
   - `design.md` — technical approach, architecture, file changes map, key decisions, risks. Template: `$CLAUDE_PLUGIN_ROOT/templates/design.md`.
   - `tasks.md` — ordered tasks grouped into waves with dependencies. Template: `$CLAUDE_PLUGIN_ROOT/templates/tasks.md`.
5. Present a plan summary to the user (counts of FRs, ACs, tasks, waves).
6. Update status: `specclaw-update-status .specclaw`.
7. **GitHub sync** (if enabled): `specclaw-gh-sync update .specclaw <change>` to attach the task checklist to the GitHub Issue.
8. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the rendered task checklist.

## Planner guardrails

When generating `tasks.md`, apply the same rules `/specclaw:build` injects into coding agents — see `references/agent-guardrails.md`. In particular: **Rule 1 (Think Before Coding)** — state assumptions explicitly in the spec/design and ask if anything is unclear, rather than picking silently between interpretations. **Rule 2 (Simplicity First)** — no speculative tasks, no over-decomposition; if three tasks could be one, make it one.
