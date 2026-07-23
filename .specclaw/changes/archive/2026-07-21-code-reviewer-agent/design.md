# Design: Code Reviewer Agent

**Change:** code-reviewer-agent
**Created:** 2026-06-21

## Architecture

### Component Map

```
plugins/specclaw/
├── agents/
│   ├── spec-author.md          (existing)
│   └── code-reviewer.md        ← NEW
├── skills/
│   ├── verify/SKILL.md         ← EDIT (add Step 3.5)
│   └── pr/SKILL.md             ← EDIT (add code_review_block check)
├── references/
│   └── agent-prompts.md        ← EDIT (add Code Reviewer prompt template)
└── templates/
    └── config.yaml             ← EDIT (add workflow.code_review flags)

README.md                       ← EDIT (document flags)
```

### Data Flow

```
/specclaw:verify
  │
  ├─ [existing] Step 1-3: collect evidence → verify agent → save verify-report.md
  │
  ├─ [NEW] Step 3.5: if workflow.code_review == true
  │   ├─ read .specclaw/config.yaml → models.review
  │   ├─ read .specclaw/changes/<change>/design.md  (may be absent → EC1)
  │   ├─ read .specclaw/changes/<change>/tasks.md   (may have no files: → EC2)
  │   ├─ spawn code-reviewer agent with:
  │   │   • changed_files_content  (from Step 1 collect)
  │   │   • design_content         (or "" if absent)
  │   │   • tasks_content          (or "" if absent)
  │   │   • spec_content           (existing)
  │   ├─ write output → .specclaw/changes/<change>/review-report.md
  │   └─ extract verdict → append one-line summary to verify-report.md
  │
  └─ [existing] Steps 4-7: save report, update status, sync, notify

/specclaw:pr
  │
  ├─ [NEW] if workflow.code_review_block == true:
  │   └─ read review-report.md → if verdict == CHANGES_REQUESTED → abort
  │
  └─ [existing] PR creation flow
```

## Agent File: `code-reviewer.md`

### Frontmatter

```yaml
---
name: code-reviewer
description: Reviews changed files for a specclaw change across 10 quality dimensions. Produces review-report.md with BLOCK/WARN/NOTE findings and a APPROVED/CHANGES_REQUESTED/APPROVED_WITH_NOTES verdict. Runs inside /specclaw:verify when workflow.code_review is true.
tools: [Read, Write, Bash]
model: sonnet
---
```

### System Prompt Structure

1. **Identity** — "You are code-reviewer, a specclaw subagent..."
2. **Inputs** — describe what will be provided in the invocation prompt
3. **Review Dimensions** — table of 10 dimensions with description + "Follow YAGNI principles, and one-liner solutions." rule called out explicitly under D3 and D4
4. **Severity Rules** — BLOCK / WARN / NOTE definitions
5. **Verdict Rules** — APPROVED / CHANGES_REQUESTED / APPROVED_WITH_NOTES
6. **Edge Case Handling** — EC1-EC5 from spec
7. **Output Format** — exact `review-report.md` template
8. **Guardrails** — inherit Rule 2 (Simplicity First) and Rule 3 (Surgical Changes) from `agent-guardrails.md`

## Prompt Template in `agent-prompts.md`

New section `## Code Reviewer Agent` after the existing `## Verify Agent` section.

Variables: `{{change_name}}`, `{{changed_files_content}}`, `{{design_content}}`, `{{tasks_content}}`, `{{spec_content}}`

The template follows the same `{{variable}}` substitution pattern as existing templates.

## Verify SKILL.md — Step 3.5

Inserted between existing Step 3 (Spawn verify agent) and Step 4 (Save report):

```markdown
## Step 3.5 — Code review (conditional)

Read `workflow.code_review` from `.specclaw/config.yaml`.

If `false` or not set, skip this step entirely.

If `true`:
1. Read `.specclaw/changes/<change>/design.md` (use empty string if absent).
2. Read `.specclaw/changes/<change>/tasks.md` (use empty string if absent).
3. Spawn the `code-reviewer` agent using the model from `config.yaml` `models.review`.
   Pass: changed files content (from Step 1), spec content, design content, tasks content.
4. Write the agent's output to `.specclaw/changes/<change>/review-report.md`.
5. Extract the verdict line from `review-report.md` and append to `verify-report.md`:
   `**Code Review:** <verdict> — <N findings: X BLOCK, Y WARN, Z NOTE>`
```

## PR SKILL.md — Block Check

New block inserted near the top of the PR skill (before branch/PR creation), after existing pre-flight checks:

```markdown
## Pre-flight: code review block (conditional)

If `workflow.code_review_block: true` in `.specclaw/config.yaml`:
1. Check if `.specclaw/changes/<change>/review-report.md` exists.
2. If it exists, read the verdict line.
3. If verdict is `CHANGES_REQUESTED`, abort with:
   "PR blocked: code review verdict is CHANGES_REQUESTED. Fix BLOCK findings in
    review-report.md then re-run /specclaw:verify."
   List all BLOCK findings from the report.
4. If `review-report.md` does not exist, warn:
   "code_review_block is enabled but no review-report.md found. Run
    /specclaw:verify first."
```

## Config Template Changes

```yaml
# Workflow enforcement
workflow:
  strict: true
  code_review: false        # Spawn code-reviewer agent during /specclaw:verify
  code_review_block: false  # Block /specclaw:pr if code review verdict is CHANGES_REQUESTED
```

## `review-report.md` Format

```markdown
# Code Review Report: <change>

**Reviewed:** YYYY-MM-DD
**Model:** <model>
**Verdict:** APPROVED | CHANGES_REQUESTED | APPROVED_WITH_NOTES

## Summary
<N findings: X BLOCK, Y WARN, Z NOTE>

## Findings

### [BLOCK] path/to/file.ts:42 — Correctness
Problem: <description>
Fix: <suggested fix>

### [WARN] path/to/file.ts:17 — YAGNI
Problem: <description>

### [NOTE] path/to/file.ts:9 — One-liner opportunity
Problem: <multi-line block>
Fix: <one-liner equivalent>

## Verdict Rationale
<One paragraph explaining the verdict>
```

## Patterns Followed

- Agent file structure mirrors `spec-author.md` (frontmatter, system prompt sections, guardrails reference)
- Prompt template structure mirrors `## Verify Agent` in `agent-prompts.md`
- Skill step numbering continues from existing verify steps (3 → 3.5 → 4)
- Config flag pattern mirrors `workflow.strict` (boolean, default false, additive)
