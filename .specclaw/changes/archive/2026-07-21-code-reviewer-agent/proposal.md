# Proposal: Code Reviewer Agent

**Created:** 2026-06-21
**Status:** 🟡 Draft

## Problem

The `/specclaw:verify` step validates acceptance criteria and runs test/lint/build commands, but it does **not** review code quality. A spec can be satisfied letter-by-letter while still shipping:

- YAGNI violations (speculative abstractions, unused parameters, over-engineered generality)
- Logic errors not covered by ACs (off-by-one, null dereference, unhandled edge cases)
- Security issues (injection risks, hardcoded secrets, missing auth guards)
- Naming/readability problems that compound over the life of the codebase
- Design drift — implementation diverges from `design.md` without justification
- Scope creep — files changed outside the declared task `files:` list
- Multi-line implementations with trivial one-liner equivalents

Projects that want code review as a gate before PR creation have no automated option in specclaw today. Human review on every change is expensive; zero review is risky.

## Proposed Solution

Add a `code-reviewer` agent (`plugins/specclaw/agents/code-reviewer.md`) that performs structured, opinionated code review on the changed files for a given change. It runs as an opt-in step inside `/specclaw:verify` — gated by a new `workflow.code_review` flag in `config.yaml`.

### Agent Behaviour

The agent receives:
- Changed files content (from `specclaw-verify collect` output)
- `design.md` — to check implementation matches intended architecture
- `tasks.md` — to check scope (files touched outside `files:` lists are flagged)
- `spec.md` — to check no spec requirement was silently dropped or over-implemented

It runs **10 review dimensions**, each producing zero or more findings:

| # | Dimension | What it checks |
|---|-----------|----------------|
| 1 | **Correctness** | Logic errors, off-by-one, null/undefined dereference, incorrect conditionals |
| 2 | **Security** | Injection risks, hardcoded secrets, missing input validation, improper auth checks |
| 3 | **YAGNI / Simplicity** | Speculative abstractions, unused parameters, "flexibility" not in spec, premature generalisation |
| 4 | **One-liner opportunities** | Multi-line blocks with idiomatic one-liner equivalents; follows "Follow YAGNI principles, and one-liner solutions" rule |
| 5 | **Naming** | Misleading names, single-letter vars outside loops, inconsistency with existing codebase convention |
| 6 | **Complexity** | Functions > ~30 lines, nesting depth > 3, cyclomatic complexity hot spots |
| 7 | **Test quality** | Missing tests for changed logic, assertions that don't test observable behaviour, tests that mirror the implementation rather than the contract |
| 8 | **Design adherence** | Implementation deviates from `design.md` without a documented reason |
| 9 | **Scope creep** | Files modified outside declared `files:` in `tasks.md` |
| 10 | **Dead code** | Added code that is never called; imports added but unused |

Each finding is tagged by severity:
- `🔴 BLOCK` — must fix before PR (security, correctness, design breach)
- `🟡 WARN` — should fix (YAGNI, complexity, dead code)
- `🟢 NOTE` — optional improvement (naming, one-liners)

### Output

`review-report.md` written to `.specclaw/changes/<change>/review-report.md`:

```
# Code Review Report: <change>

**Reviewed:** YYYY-MM-DD
**Verdict:** APPROVED | CHANGES_REQUESTED | APPROVED_WITH_NOTES

## Summary
<N findings: X BLOCK, Y WARN, Z NOTE>

## Findings
### [BLOCK] path/to/file.ts:42 — Correctness
<description + suggested fix>

### [WARN] path/to/other.ts:17 — YAGNI
<description>

...

## Verdict Rationale
<One paragraph>
```

Verdict rules:
- `APPROVED` — zero BLOCK findings
- `CHANGES_REQUESTED` — any BLOCK finding
- `APPROVED_WITH_NOTES` — zero BLOCK, one or more WARN/NOTE

### Config Integration

New flag in `config.yaml` template:

```yaml
workflow:
  strict: true
  code_review: false        # Enable automated code reviewer agent on verify
  code_review_block: false  # If true, CHANGES_REQUESTED verdict blocks /specclaw:pr
```

When `code_review: true`, `/specclaw:verify` spawns the `code-reviewer` agent **after** the existing verify agent (Step 3.5). The review verdict is appended to Step 5 status update logic; `code_review_block: true` causes `CHANGES_REQUESTED` to propagate as a hard blocker to `/specclaw:pr`.

### Integration Point in Verify Skill

Step 3.5 (new, inserted between Step 3 and Step 4 of verify):

```
## Step 3.5 — Code review (if workflow.code_review: true)

Spawn code-reviewer agent with the verify context payload + design.md + tasks.md.
Save output as `.specclaw/changes/<change>/review-report.md`.
Append review verdict to the verify-report.md summary section.
```

## Scope

### In Scope
- New `plugins/specclaw/agents/code-reviewer.md`
- Edit `plugins/specclaw/skills/verify/SKILL.md` — add Step 3.5
- Edit `plugins/specclaw/templates/config.yaml` — add `workflow.code_review` + `workflow.code_review_block`
- Edit `plugins/specclaw/references/agent-prompts.md` — add Code Reviewer Agent prompt template
- Update `README.md` — document the new config flags
- Update `plugins/specclaw/skills/pr/SKILL.md` — respect `code_review_block` before allowing PR

### Out of Scope
- Inline auto-fix of review findings (future `/specclaw:fix-review`)
- Per-dimension enable/disable flags (add later if needed)
- Diff-only review mode (agent reviews full changed-file content, not patch hunks)
- Integration with external review tools (GitHub PR review comments via gh API)

## Impact

- Files changed: ~5
- Complexity: medium
- Risk: low — purely additive, opt-in flag defaults to `false`

## Open Questions

1. Should `review-report.md` merge into `verify-report.md` as a new section, or stay a separate file? (Proposal: separate, keeps concerns clean)
2. Should `code_review_block` default to `false` or follow `workflow.strict`? (Proposal: always default `false` — let projects opt in to hard blocking explicitly)
3. Should the reviewer use `models.review` (Sonnet) or `models.planning` (Opus)? (Proposal: `models.review` — code review is pattern-matching at inference speed, not deep reasoning)
