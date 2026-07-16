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
3. Analyze the existing codebase (file structure, patterns, dependencies relevant to the change). **Also read `.specclaw/context.md` if it exists** — it contains project-level coding rules, patterns, architecture decisions, and constraints; apply them throughout spec, design, and tasks generation.
   - **Codebase survey:** build a structured survey and keep it in your working context for spec/design/tasks generation: top-two-level directory summary (e.g. from `git ls-files | cut -d/ -f1-2 | sort -u`), detected manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `*.csproj`, `pom.xml`, `Makefile`, ...) and the languages/tooling they imply, and where tests live.
   - **Discovered project docs:** run `specclaw-discover-context .specclaw list` to see ranked candidate docs (rank, line count, path), then `specclaw-discover-context .specclaw emit` for the budget-capped digest. Read the digest and apply the project's documented conventions, constraints, and non-goals throughout planning. Prefer docs most relevant to this change when deciding what to read in depth. **Cite your evidence:** when a spec requirement, design decision, or task constraint comes from a discovered doc, name the doc path and quote the exact line(s) it rests on — never attribute a claim to a doc without a quote. If discovery is disabled or finds nothing, both commands print nothing — skip this step silently.
   - **Promoted spec knowledge:** read `.specclaw/knowledge/spec-guidelines.md` if it exists — it holds spec/design guidance promoted from earlier build learnings; apply it when writing `spec.md` and `design.md`.
4. Generate three files in `.specclaw/changes/<change>/`:
   - `spec.md` — functional requirements, non-functional requirements, acceptance criteria, edge cases.
     - **If `--author-spec` is set:** invoke the `spec-author` subagent via the `Agent` tool with `subagent_type: "spec-author"` to author the spec interactively. After the agent writes the file, **STOP and require explicit user approval** (e.g. "approved", "yes", "go") before proceeding to `design.md` and `tasks.md`. Do not generate the remaining files until the user approves.
     - **Otherwise:** generate `spec.md` directly using `$CLAUDE_PLUGIN_ROOT/templates/spec.md` as a starting template (single-shot, no dialogue).
     - **If `spec.md` already exists** (e.g. authored previously via `/specclaw:author-spec`): do not overwrite it; skip the spec step and proceed to `design.md` / `tasks.md`.
   - `design.md` — technical approach, architecture, file changes map, key decisions, risks. Template: `$CLAUDE_PLUGIN_ROOT/templates/design.md`. **When discovery produced docs, add a "Grounding sources" section** listing the discovered files you actually used — each entry cites the path plus the specific convention or quoted line applied. The paper trail for what informed the design, backed by quotable evidence rather than vague attribution.
   - `tasks.md` — ordered tasks grouped into waves with dependencies. Template: `$CLAUDE_PLUGIN_ROOT/templates/tasks.md`.
5. Present a plan summary to the user (counts of FRs, ACs, tasks, waves).
6. Update status: `specclaw-update-status .specclaw`.
7. **GitHub sync** (if enabled): `specclaw-gh-sync update .specclaw <change>` to attach the task checklist to the GitHub Issue.
8. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the rendered task checklist.

## Planner guardrails

When generating `tasks.md`, apply the same rules `/specclaw:build` injects into coding agents — see `references/agent-guardrails.md`. In particular: **Rule 1 (Think Before Coding)** — state assumptions explicitly in the spec/design and ask if anything is unclear, rather than picking silently between interpretations. **Rule 2 (Simplicity First)** — no speculative tasks, no over-decomposition; if three tasks could be one, make it one.
