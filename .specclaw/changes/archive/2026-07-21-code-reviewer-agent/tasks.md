# Tasks: Code Reviewer Agent

**Change:** code-reviewer-agent
**Created:** 2026-06-21
**Total Tasks:** 5

## Summary

Five tasks in two waves. Wave 1 creates the agent and prompt template (independent). Wave 2 wires the agent into verify and pr skills, adds config flags, and updates docs. All five tasks are small-medium file edits; no new shell scripts or binaries needed.

## Tasks

### Wave 1 — Create agent and prompt template

- [x] `T1` — Create `code-reviewer` subagent
  - Files: `plugins/specclaw/agents/code-reviewer.md` (new)
  - Estimate: medium
  - Depends: —
  - Notes: Frontmatter `name: code-reviewer`, `description`, `tools: [Read, Write, Bash]`, `model: sonnet`.
    System prompt sections:
    (a) Identity — "You are code-reviewer, a specclaw subagent that reviews code quality."
    (b) Inputs — changed files content, spec content, design content (may be empty), tasks content (may be empty)
    (c) Review Dimensions table — 10 rows. D3 (YAGNI/Simplicity) and D4 (One-liner opportunities) MUST include the rule: "Follow YAGNI principles, and one-liner solutions."
    (d) Severity definitions — BLOCK (security/correctness/design breach), WARN (YAGNI/complexity/dead code), NOTE (naming/one-liners)
    (e) Verdict rules — APPROVED / CHANGES_REQUESTED / APPROVED_WITH_NOTES
    (f) Edge case handling — EC1 (no design.md → skip D8), EC2 (no files: in tasks.md → skip D9), EC3 (no changed files → APPROVED with note), EC4 (overwrite existing report), EC5 (missing models.review → default sonnet)
    (g) Output format — exact review-report.md template from design.md
    (h) Guardrails — reference `references/agent-guardrails.md` Rules 2 and 3

- [x] `T2` — Add Code Reviewer Agent prompt template to `agent-prompts.md`
  - Files: `plugins/specclaw/references/agent-prompts.md` (edit)
  - Estimate: small
  - Depends: —
  - Notes: Add `## Code Reviewer Agent` section after the existing `## Verify Agent` section.
    Variables: `{{change_name}}`, `{{changed_files_content}}`, `{{design_content}}`, `{{tasks_content}}`, `{{spec_content}}`.
    Template body mirrors the structure of the Verify Agent template — header, inputs, task description, output format.
    Keep the template under 150 lines.

### Wave 2 — Wire into verify/pr, config, docs

- [x] `T3` — Add Step 3.5 to `/specclaw:verify` SKILL.md
  - Files: `plugins/specclaw/skills/verify/SKILL.md` (edit)
  - Estimate: small
  - Depends: T1
  - Notes: Insert `## Step 3.5 — Code review (conditional)` between existing Step 3 and Step 4.
    Step reads `workflow.code_review` from config; if false/absent, silent skip.
    If true: read design.md and tasks.md (empty string if absent), spawn `code-reviewer` agent with `models.review` model,
    write output to `review-report.md`, extract verdict line and append one-line summary to verify-report.md.
    Format of appended line: `**Code Review:** <verdict> — <N findings: X BLOCK, Y WARN, Z NOTE>`

- [x] `T4` — Add code_review_block pre-flight check to `/specclaw:pr` SKILL.md
  - Files: `plugins/specclaw/skills/pr/SKILL.md` (edit)
  - Estimate: small
  - Depends: T1
  - Notes: Insert a new "Pre-flight: code review block" section near the top of the PR skill, after existing pre-flight checks.
    If `workflow.code_review_block: true`: read review-report.md; if verdict is CHANGES_REQUESTED abort with BLOCK findings list;
    if review-report.md missing, warn and continue (don't hard-block for missing file — that would be too aggressive).

- [x] `T5` — Add config flags and update README
  - Files: `plugins/specclaw/templates/config.yaml` (edit), `README.md` (edit)
  - Estimate: small
  - Depends: —
  - Notes: In config.yaml, add under `workflow:`:
    ```yaml
    code_review: false        # Spawn code-reviewer agent during /specclaw:verify
    code_review_block: false  # Block /specclaw:pr if code review verdict is CHANGES_REQUESTED
    ```
    In README.md, add a "Code Review" subsection under the Configuration section (or workflow section).
    Two-sentence description of each flag. Keep it brief.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
