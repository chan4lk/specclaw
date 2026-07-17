# Spec: Living Project Context

**Change:** living-project-context
**Created:** 2026-07-08
**Status:** 🟡 Draft

## Overview

Add `.specclaw/context.md` — a living architecture document that captures project-level coding rules, style guides, patterns, and decisions. All lifecycle skills load it automatically. The document stays current by being rewritten (not appended) after each merged change.

## Requirements

### Functional Requirements

- FR1: `/specclaw:context` skill lets operators view, add, and edit sections of `.specclaw/context.md`.
- FR2: `context.md` is created from a template on first use. Template has structured sections: Architecture Overview, Coding Style, Key Patterns, Technology Decisions, Constraints.
- FR3: `context.md` is committed to the project repo (tracked in git, not gitignored).
- FR4: After a PR is merged via `/specclaw:pr` or `/specclaw:pr-azdo`, `specclaw-update-context` rewrites `context.md` to incorporate decisions, patterns, and conventions introduced by the change.
- FR5: The update is architecture-doc style: stale or superseded information is replaced; new information is merged in. Git history is the audit trail.
- FR6: `specclaw-build-context` injects `context.md` content into every coding agent payload when the file exists.
- FR7: `plan`, `build`, and `verify` skill instructions reference `context.md` as mandatory reading before generating output.
- FR8: `CLAUDE.md` (plugin root) documents `context.md` — what it is, when to update it, how skills use it.

### Non-Functional Requirements

- NFR1: Graceful degradation — all existing skills work unchanged if `context.md` is absent.
- NFR2: No config flag required — context loading and auto-update are always-on.
- NFR3: `context.md` update must not block PR creation; it runs after the PR URL is saved.
- NFR4: `specclaw-update-context` must be idempotent — safe to re-run.

## Acceptance Criteria

- AC1: Running `/specclaw:context show` prints the current `context.md` or a message if not yet created.
- AC2: Running `/specclaw:context add` lets the operator describe a rule/pattern; the skill writes it into the appropriate section of `context.md`.
- AC3: After `/specclaw:pr` completes, `context.md` is updated to reflect decisions from the merged change.
- AC4: A coding agent spawned via `specclaw-build-context` receives `context.md` content in its prompt when the file exists.
- AC5: A coding agent spawned when `context.md` is absent receives no error — just no context section.
- AC6: `context.md` is present in git (not in `.gitignore`).
- AC7: `plan` SKILL.md instructs the planner to read `context.md` before generating spec/design/tasks.
- AC8: `verify` SKILL.md instructs the verifier to check implementation against `context.md` rules.

## Edge Cases

- EC1: `context.md` doesn't exist yet when a PR is merged — `specclaw-update-context` creates it from template.
- EC2: A change has no design.md or verify-report.md (e.g. early abandon) — `specclaw-update-context` skips gracefully with a warning.
- EC3: `context.md` is very large (>200 lines) — build-context truncates to MAX_CONTEXT_LINES (150) with a notice.
- EC4: Operator runs `/specclaw:context add` when `context.md` doesn't exist — creates from template first.

## Dependencies

- `specclaw-build-context` (existing) — needs context injection block added.
- `specclaw-pr` (existing) — needs post-PR context update step added.
- `specclaw-pr-azdo` (existing) — same as above.
- `plugins/specclaw/skills/plan/SKILL.md` — needs context.md reference added.
- `plugins/specclaw/skills/verify/SKILL.md` — needs context.md reference added.

## Notes

- The `/specclaw:context` skill is AI-driven (no new bash script needed for the interactive editing path — the LLM reads and rewrites the file directly following the skill instructions).
- `specclaw-update-context` is a bash script because it must run reliably in the `pr` flow without user interaction.
