# Tasks: Living Project Context

**Change:** living-project-context
**Created:** 2026-07-08
**Total Tasks:** 8

## Summary

8 tasks across 3 waves. Wave 1 creates the new artifacts (template, script, skill). Wave 2 wires context into existing skills and build-context. Wave 3 adds documentation and bumps version.

## Tasks

### Wave 1 — New artifacts

- [x] `T1` — Create `plugins/specclaw/templates/context.md` seed template
  - Files: `plugins/specclaw/templates/context.md`
  - Estimate: small
  - Depends: none
  - Notes: Structured sections — Architecture Overview, Coding Style & Conventions, Key Patterns, Technology Decisions, Constraints, Recent Decisions. Each section has a placeholder comment.

- [x] `T2` — Create `plugins/specclaw/bin/specclaw-update-context` script
  - Files: `plugins/specclaw/bin/specclaw-update-context`
  - Estimate: medium
  - Depends: T1
  - Notes: Bash script. Args: `<specclaw_dir> <change_name>`. Seeds from template if context.md absent. Reads proposal.md + design.md + verify-report.md from the change. Uses LLM synthesis via stdout — outputs a structured prompt that the pr skill uses to drive an LLM rewrite of context.md. Must exit 0 always. Make executable (chmod +x).

- [x] `T3` — Create `plugins/specclaw/skills/context/SKILL.md`
  - Files: `plugins/specclaw/skills/context/SKILL.md`
  - Estimate: small
  - Depends: T1
  - Notes: Valid YAML frontmatter (quote description if it contains colons). Sub-commands: show (print context.md or "not created yet"), add (operator describes a rule; LLM writes it into the correct section), edit (operator specifies section + new content; LLM rewrites that section), reset (recreate from template). Gracefully seeds context.md from template if absent before add/edit.

### Wave 2 — Wire into existing skills

- [x] `T4` — Update `specclaw-build-context` to inject context.md into agent payload
  - Files: `plugins/specclaw/bin/specclaw-build-context`
  - Estimate: small
  - Depends: T1
  - Notes: After the KNOWLEDGE_SECTION block, add a CONTEXT_SECTION block: if `.specclaw/context.md` exists, read it (truncate to 150 lines with notice if longer) and inject as `## Project Context\n<contents>`. Insert CONTEXT_SECTION into the final PROMPT heredoc after KNOWLEDGE_SECTION.

- [x] `T5` — Update `specclaw-pr` to call `specclaw-update-context` post-PR
  - Files: `plugins/specclaw/bin/specclaw-pr`
  - Estimate: small
  - Depends: T2
  - Notes: After saving PR URL to status.md, call `specclaw-update-context "$SPECCLAW_DIR" "$CHANGE_NAME"` in a subshell (set +e; ... ; set -e) so errors don't abort the script. If context.md changed, commit it: `git add .specclaw/context.md && git commit -m "chore(context): update project context after <change>"`.

- [x] `T6` — Update plan, verify, pr, pr-azdo SKILL.md files to reference context.md
  - Files: `plugins/specclaw/skills/plan/SKILL.md`, `plugins/specclaw/skills/verify/SKILL.md`, `plugins/specclaw/skills/pr/SKILL.md`, `plugins/specclaw/skills/pr-azdo/SKILL.md`
  - Estimate: small
  - Depends: T3
  - Notes: plan — add after "Analyze the existing codebase": "Also read `.specclaw/context.md` (if present) — it contains project-level coding rules, patterns, and architecture decisions; apply them in spec/design/tasks generation." verify — add after ensure-init: "If `.specclaw/context.md` exists, load it and verify that the implementation respects its rules and constraints." pr — add new step after PR URL saved: "Run `specclaw-update-context .specclaw <change>` to rewrite context.md with decisions from this change. Commit context.md if changed." pr-azdo — same as pr.

### Wave 3 — Documentation and version bump

- [x] `T7` — Create `plugins/specclaw/CLAUDE.md` documenting context.md
  - Files: `plugins/specclaw/CLAUDE.md`
  - Estimate: small
  - Depends: T3, T4, T6
  - Notes: Document what context.md is, where it lives, how skills use it, how to create it (/specclaw:context), how it auto-updates. Keep concise — 1-2 paragraphs per section. This becomes the plugin-level CLAUDE.md that Claude Code loads when the plugin is active.

- [x] `T8` — Bump plugin version 0.4.4 → 0.4.5
  - Files: `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Depends: T7
  - Notes: Patch bump. Both files must stay in sync.

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
