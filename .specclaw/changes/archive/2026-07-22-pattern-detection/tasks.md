# Tasks: Cross-Change Pattern Detection

**Change:** pattern-detection
**Created:** 2026-03-28
**Total Tasks:** 3

## Summary

Create patterns registry, detection script, and SKILL.md integration.

## Tasks

### Wave 1 — Detection script and registry

- [x] `T1` — Create detect-patterns.sh and patterns.md template
  - Files: skill/scripts/detect-patterns.sh, skill/templates/patterns.md
  - Estimate: medium
  - Notes: detect-patterns.sh has three modes. (1) Scan: `detect-patterns.sh .specclaw scan <change>` — reads errors.md and learnings.md for this change, extracts keywords/categories, compares against existing patterns.md entries. If match found (same category + overlapping keywords), increment recurrence count and add occurrence link. If no match, register new pattern with PAT-NNN ID, recurrence 1. (2) List: `detect-patterns.sh .specclaw list [--min-recurrence N]` — shows all patterns with recurrence counts. (3) Promote: `detect-patterns.sh .specclaw promote <pat-id>` — marks pattern as promoted, outputs the prevention rule. Auto-promotion threshold: recurrence >= 3 (flag with ⚠️ in list output). Keyword matching: extract nouns/verbs from summaries, match if 2+ keywords overlap AND same category. Keep it simple — grep-based, not NLP. patterns.md lives at .specclaw/patterns.md (global, not per-change).

### Wave 2 — Integration

- [x] `T2` — Update SKILL.md with specclaw patterns command
  - Files: skill/SKILL.md
  - Depends: T1
  - Estimate: small
  - Notes: Add ### specclaw patterns section. Document trigger patterns, scan/list/promote modes. Note that scan runs automatically during post-build review. Mention auto-promotion threshold (3 occurrences). Add patterns.md to directory structure listing.

- [x] `T3` — Hook pattern scan into post-build review flow
  - Files: skill/SKILL.md
  - Depends: T1
  - Estimate: small
  - Notes: In the post-build review step (Step 5), add: after logging learnings, run `detect-patterns.sh .specclaw scan <change>` to check for recurring patterns. If any patterns hit promotion threshold (>= 3), alert the user. Keep the addition minimal — 3-4 lines in the existing review step.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
