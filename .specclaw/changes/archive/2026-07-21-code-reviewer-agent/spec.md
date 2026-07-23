# Spec: Code Reviewer Agent

**Change:** code-reviewer-agent
**Created:** 2026-06-21
**Status:** approved

## Overview

Add a `code-reviewer` subagent to specclaw that performs structured, opinionated code review on changed files during the verify step. The agent is opt-in via `workflow.code_review: true` in `config.yaml`. It runs after the existing verify agent (AC check), reviews 10 dimensions of code quality, tags findings by severity, and outputs `review-report.md`. A second flag, `workflow.code_review_block: true`, lets projects hard-block PR creation when the verdict is `CHANGES_REQUESTED`.

## Functional Requirements

**FR1** — The `code-reviewer` agent SHALL be defined at `plugins/specclaw/agents/code-reviewer.md` with frontmatter fields: `name`, `description`, `tools: [Read, Write, Bash]`, `model: sonnet`.

**FR2** — The agent SHALL review changed files across exactly 10 dimensions: Correctness, Security, YAGNI/Simplicity, One-liner opportunities, Naming, Complexity, Test quality, Design adherence, Scope creep, Dead code.

**FR3** — Each finding SHALL be tagged with one of three severity levels: `🔴 BLOCK`, `🟡 WARN`, `🟢 NOTE`.

**FR4** — The agent SHALL output verdict as exactly one of: `APPROVED` (zero BLOCK findings), `CHANGES_REQUESTED` (one or more BLOCK findings), `APPROVED_WITH_NOTES` (zero BLOCK, one or more WARN/NOTE).

**FR5** — The agent SHALL write its output to `.specclaw/changes/<change>/review-report.md` in the format specified in the Code Reviewer Agent prompt template.

**FR6** — `/specclaw:verify` SKILL.md SHALL include a new Step 3.5 that: reads `workflow.code_review` from config; if `true`, spawns the `code-reviewer` agent with changed files + `design.md` + `tasks.md`; saves output as `review-report.md`; appends review verdict to the verify-report summary.

**FR7** — `plugins/specclaw/templates/config.yaml` SHALL add two new fields under `workflow:`:
- `code_review: false` — enables the code reviewer agent on verify
- `code_review_block: false` — causes `CHANGES_REQUESTED` verdict to block `/specclaw:pr`

**FR8** — `plugins/specclaw/references/agent-prompts.md` SHALL contain a new `## Code Reviewer Agent` section with the full prompt template including the 10-dimension review table and output format specification.

**FR9** — `/specclaw:pr` SKILL.md SHALL check `workflow.code_review_block`; if `true` and `review-report.md` verdict is `CHANGES_REQUESTED`, abort with a message listing the BLOCK findings.

**FR10** — `README.md` SHALL document the two new config flags with a brief description of the code review feature.

**FR11** — The "Follow YAGNI principles, and one-liner solutions." rule SHALL be explicitly stated in the agent system prompt under the Dimension 3 (YAGNI/Simplicity) and Dimension 4 (One-liner opportunities) descriptions.

## Non-Functional Requirements

**NFR1** — Opt-in only: default value of `workflow.code_review` is `false`; existing projects are unaffected until they set the flag.

**NFR2** — Agent uses `models.review` model (Sonnet) — not Opus — keeping cost proportional to a pattern-matching task.

**NFR3** — Step 3.5 is silently skipped when `workflow.code_review: false`; no output, no error, no performance impact.

**NFR4** — The agent system prompt is ≤ 800 words — concise enough to fit in a single context payload without crowding changed-file content.

**NFR5** — `review-report.md` is a separate file from `verify-report.md`; the verify skill appends only a one-line summary of the review verdict to `verify-report.md`, not the full report.

## Acceptance Criteria

**AC1** — GIVEN `workflow.code_review: false` WHEN `/specclaw:verify` runs THEN `review-report.md` is NOT created and verify behaviour is identical to pre-change.

**AC2** — GIVEN `workflow.code_review: true` WHEN `/specclaw:verify` runs THEN `review-report.md` is created at `.specclaw/changes/<change>/review-report.md`.

**AC3** — GIVEN a `review-report.md` with zero BLOCK findings WHEN the file is read THEN the verdict line reads `APPROVED` or `APPROVED_WITH_NOTES`.

**AC4** — GIVEN a `review-report.md` with one or more BLOCK findings WHEN the file is read THEN the verdict line reads `CHANGES_REQUESTED`.

**AC5** — GIVEN `workflow.code_review_block: true` AND `review-report.md` verdict is `CHANGES_REQUESTED` WHEN `/specclaw:pr` runs THEN it aborts and prints the BLOCK findings before creating a PR.

**AC6** — GIVEN `workflow.code_review_block: false` AND `review-report.md` verdict is `CHANGES_REQUESTED` WHEN `/specclaw:pr` runs THEN the PR is created (review findings shown as a warning, not a hard block).

**AC7** — GIVEN a changed file with a multi-line implementation that has a one-liner equivalent WHEN the code reviewer runs THEN at least one finding appears under Dimension 4 (One-liner opportunities).

**AC8** — GIVEN `plugins/specclaw/templates/config.yaml` WHEN inspected THEN it contains `code_review: false` and `code_review_block: false` under the `workflow:` key.

**AC9** — GIVEN `README.md` WHEN inspected THEN it mentions `workflow.code_review` and `workflow.code_review_block` with descriptions.

**AC10** — GIVEN `plugins/specclaw/agents/code-reviewer.md` WHEN inspected THEN the system prompt explicitly states "Follow YAGNI principles, and one-liner solutions." in the dimension descriptions.

## Edge Cases

**EC1** — `design.md` does not exist for the change (e.g. a tiny fix skipped design phase) — agent should skip Dimension 8 (Design adherence) and note "design.md not found — skipping design adherence check."

**EC2** — `tasks.md` has no `files:` declarations — agent skips Dimension 9 (Scope creep) and notes "No files: declared in tasks.md — skipping scope check."

**EC3** — Changed files list is empty (no files collected by `specclaw-verify collect`) — agent outputs a `review-report.md` with verdict `APPROVED` and a note "No changed files to review."

**EC4** — `review-report.md` already exists from a prior verify run — Step 3.5 overwrites it (same as verify-report.md behaviour).

**EC5** — `workflow.code_review: true` but `models.review` is not set in config — agent falls back to `anthropic/claude-sonnet-4-6` (hardcoded default in agent frontmatter).

## Dependencies

- Existing `specclaw-verify collect` output format (changed files content)
- `models.review` config key (already exists in `templates/config.yaml`)
- `plugins/specclaw/agents/spec-author.md` — structural reference for new agent file
- `plugins/specclaw/skills/verify/SKILL.md` — edit target
- `plugins/specclaw/skills/pr/SKILL.md` — edit target for block check
- `plugins/specclaw/references/agent-prompts.md` — edit target for new prompt section

## Notes

- The proposal's open question #1 (merge vs. separate report file) resolved: separate `review-report.md`, one-line summary appended to `verify-report.md`.
- Open question #2 (code_review_block default) resolved: always `false` — opt-in to hard blocking.
- Open question #3 (which model) resolved: `models.review` (Sonnet).
- Future: `/specclaw:fix-review` skill could read `review-report.md` BLOCK findings and spawn a coding agent to address them.
