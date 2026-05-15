# Learnings: claude-plugin-packaging

Build learnings, spec gaps, and patterns discovered.

**Categories:** spec_gap | design_gap | pattern | best_practice | agent_issue

---

## [L1] design_gap — specclaw-validate-change count_incomplete uses naive '^- ...

**When:** 2026-05-15 07:37 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
specclaw-validate-change count_incomplete uses naive '^- \[ \]' grep that matches code-block examples in tasks.md legend

### Action
Update count_incomplete to ignore content inside fenced code blocks, or change tasks.md template to use indented example block (4-space prefix) instead of fenced block

---

## [L2] agent_issue — specclaw-azdo-issue create exited silently with exit 1 wh...

**When:** 2026-05-15 14:51 UTC
**Category:** agent_issue
**Priority:** high
**Status:** pending

### Detail
specclaw-azdo-issue create exited silently with exit 1 when grep pipeline in existing_wi_id() returned no match — set -e + pipefail propagated through command substitution

### Action
Always append || true to grep | head | sed pipelines used inside command substitution; consider documenting this pattern in references/agent-prompts.md

---
