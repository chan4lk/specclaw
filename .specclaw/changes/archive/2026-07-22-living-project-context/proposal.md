# Proposal: Living Project Context

**Created:** 2026-07-08
**Status:** ✅ Approved

## Problem

Specclaw has no structured way to capture project-level coding rules, style guides, or architectural constraints. The `plan` and `build` skills analyze the codebase ad-hoc each time, which means:

- Coding conventions discovered during one change are lost by the next
- Style guides or architecture rules must be re-explained each session
- As proposals are merged, the project evolves but specclaw has no record of those decisions

This leads to inconsistent code generation and repeated context-setting by the operator.

## Proposed Solution

Add a `/specclaw:context` skill backed by `.specclaw/context.md` — a living document of project rules that all lifecycle skills (plan, build, verify) automatically load.

Two parts:

1. **`/specclaw:context` skill** — lets the operator register or update project rules interactively: coding style, architecture constraints, naming conventions, banned patterns, preferred libraries. Writes to `.specclaw/context.md`.

2. **Auto-update on merge** — the `/specclaw:pr` (and `pr-azdo`) step appends a "Context delta" section to `context.md` when a proposal is merged: new patterns introduced, decisions made, conventions established. The `archive` skill also triggers a context review.

All skills that currently do ad-hoc codebase analysis (`plan`, `build`, `verify`) prepend `context.md` to their working context before generating output.

## Scope

### In Scope
- New `/specclaw:context` skill with `show`, `add`, `edit`, `reset` sub-commands
- `.specclaw/context.md` file (tracked in git alongside other specclaw artifacts)
- `specclaw-build-context` script enhancement (or new `specclaw-update-context` script) to append delta from merged changes
- `plan`, `build`, `verify` skills updated to load `context.md` if it exists
- `pr` and `pr-azdo` skills updated to append context delta post-merge

### Out of Scope
- Automatic codebase scanning to infer rules (operator provides them explicitly)
- Per-change context overrides (one global context file for now)
- Context versioning / history (context.md is a living doc, git history is the record)

## Impact

- **Files affected:** ~8 (new skill, new/updated scripts, 4 updated skills)
- **Complexity:** medium
- **Risk:** low (additive; existing skills degrade gracefully if context.md absent)

## Decisions (Approved)

1. `context.md` is committed to the project repo alongside `.specclaw/` — shareable across team.
2. Auto-update is always-on — no config flag needed.
3. Architecture-doc model: context.md is rewritten to stay current. Old/stale sections replaced, not appended. Git history is the audit trail.

---

**To proceed:** Review this proposal and approve to begin planning.
