# Design: Living Project Context

**Change:** living-project-context
**Created:** 2026-07-08

## Technical Approach

Add a `context.md` artifact to the `.specclaw/` directory. It is a structured markdown document with named sections. Skills that generate code read it; the `pr` skill rewrites it after merge.

Two entry points:
1. **Interactive** — `/specclaw:context` skill. LLM reads and rewrites `context.md` per operator instruction (show, add, edit, reset).
2. **Automatic** — `specclaw-update-context` bash script, called by `specclaw-pr` after PR creation. Reads change artifacts (proposal.md, design.md, verify-report.md) and rewrites `context.md` to incorporate what was learned.

`specclaw-build-context` injects a `## Project Context` block into every agent payload when `context.md` exists.

## Architecture

```
.specclaw/
  context.md              ← living architecture doc (new, tracked in git)

plugins/specclaw/
  bin/
    specclaw-build-context  ← inject context.md into agent payload (modified)
    specclaw-pr             ← call specclaw-update-context post-PR (modified)
    specclaw-update-context ← new: rewrite context.md after merge
  skills/
    context/SKILL.md        ← new: /specclaw:context skill
    plan/SKILL.md           ← add: load context.md before planning
    verify/SKILL.md         ← add: check impl against context.md rules
    pr/SKILL.md             ← add: call specclaw-update-context post-merge
    pr-azdo/SKILL.md        ← add: same
  templates/
    context.md              ← new: seed template for new projects
  CLAUDE.md                 ← add: context.md documentation (new root CLAUDE.md)
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-update-context` | Create | Rewrites context.md from change artifacts |
| `plugins/specclaw/skills/context/SKILL.md` | Create | Interactive context management skill |
| `plugins/specclaw/templates/context.md` | Create | Seed template with empty sections |
| `plugins/specclaw/bin/specclaw-build-context` | Modify | Inject context.md into agent payload |
| `plugins/specclaw/bin/specclaw-pr` | Modify | Call specclaw-update-context post-PR |
| `plugins/specclaw/skills/plan/SKILL.md` | Modify | Load context.md before planning |
| `plugins/specclaw/skills/verify/SKILL.md` | Modify | Check against context.md rules |
| `plugins/specclaw/skills/pr/SKILL.md` | Modify | Document context auto-update step |
| `plugins/specclaw/skills/pr-azdo/SKILL.md` | Modify | Same as pr |
| `plugins/specclaw/CLAUDE.md` | Create | Plugin-level docs for context.md |

## Data Model Changes

`context.md` structure (named sections, LLM-parseable):

```markdown
# Project Context

_Last updated: YYYY-MM-DD by change: <change-name>_

## Architecture Overview
[High-level system description, key components, entry points]

## Coding Style & Conventions
[Language version, formatting rules, naming conventions, comment policy]

## Key Patterns
[Reusable patterns found across the codebase — auth, error handling, data access, etc.]

## Technology Decisions
[Why X library was chosen over Y, version pins and why, migration paths]

## Constraints
[What NOT to do — banned patterns, deprecated APIs, performance floor, security rules]

## Recent Decisions
[Last 5 significant decisions from merged changes — pruned on each update]
```

## API Changes

`specclaw-update-context` interface:
```
specclaw-update-context <specclaw_dir> <change_name>
```
- Reads: `.specclaw/changes/<change_name>/{proposal.md,design.md,verify-report.md}`
- Reads existing `.specclaw/context.md` (or seeds from template if absent)
- Writes: `.specclaw/context.md` (rewritten in place)
- Exit 0 always (post-PR step must not fail the workflow)

`specclaw-build-context` change:
- After loading guardrails and knowledge base, if `.specclaw/context.md` exists, inject:
  ```
  ## Project Context
  <contents of context.md, truncated to MAX_CONTEXT_LINES if needed>
  ```

## Key Decisions

- **Architecture-doc model (not append log):** `specclaw-update-context` rewrites `context.md` each time. Stale entries are removed or updated. This keeps the document concise and authoritative. Git history is the audit trail for what was removed.
- **AI-driven interactive editing:** The `/specclaw:context` skill delegates to the LLM for interactive editing rather than a bash TUI. The LLM reads context.md and rewrites sections per operator instruction. No new bash interactivity needed.
- **Always-on, no config flag:** Context loading and auto-update are unconditional. Simpler mental model. Graceful degradation when file absent.
- **Committed to repo:** `context.md` lives alongside `.specclaw/` and is tracked in git. Enables team sharing and PR review of context changes.
- **`specclaw-update-context` is bash + LLM prompt via heredoc:** The script invokes the LLM (via the agent calling it) by outputting a structured prompt to stdout, which the calling skill uses as its agent task. This avoids direct bash-only LLM calls while keeping the integration point clean.

  **Revised:** The script itself is pure bash — it extracts key decisions from change artifacts using text parsing, then writes them into context.md sections. No LLM call needed in the script; the pr skill orchestrates an LLM call to do the synthesis if needed.

- **`specclaw-pr` modification:** Add step after PR URL is saved: run `specclaw-update-context .specclaw <change>` and commit `context.md` if changed.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `specclaw-update-context` overwrites important context | Architecture-doc rewrite is done by LLM with full prior context — it merges, not blindly replaces. Git history recovers anything lost. |
| context.md grows too large | Truncate in build-context (MAX_CONTEXT_LINES=150). `specclaw-update-context` prunes Recent Decisions to last 5. |
| pr step fails due to context update error | Script exits 0 always; errors are warned but do not block the PR flow. |
| Coding agents hallucinate rules from context.md | Operators review context.md like any code artifact. Git diff on context.md is reviewable in PR. |
