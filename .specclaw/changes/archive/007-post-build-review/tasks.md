# Tasks: Post-Build Review

**Change:** post-build-review
**Created:** 2026-03-28
**Total Tasks:** 1

## Summary

Single task: update SKILL.md build flow to add post-build review prompt and scope deviation check. Also add config option.

## Tasks

### Wave 1

- [x] `T1` — Add post-build review step to SKILL.md and config template
  - Files: skill/SKILL.md, skill/templates/config.yaml
  - Estimate: small
  - Notes: (1) In SKILL.md build flow, after the finalize step and before notify, add a "Post-Build Review" step that prompts the agent to evaluate: spec clarity, design accuracy, scope deviations (files changed outside task declarations), agent struggles, and patterns worth capturing. The agent should auto-log findings via log-learning.sh. (2) Add `automation.post_build_review: true` to config.yaml template with a comment. (3) In the review step, check if any git-changed files aren't in any task's file list — flag as scope deviation. (4) Keep it lightweight — the review prompt should be ~150 words max.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
