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

## [L3] design_gap — specclaw-validate-change count_incomplete() matches '- [ ...

**When:** 2026-05-20 17:10 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
specclaw-validate-change count_incomplete() matches '- [ ]' inside the tasks.md template legend's 'Task format' code fence — false positive blocks verify even when all tasks are complete. Affects the default template at /templates/tasks.md.

### Action
Either (a) make count_incomplete skip lines inside code fences, or (b) change the legend example to use a non-matching marker (e.g. '* [ ]' or indented inside the fence). Best fixed in a follow-up change.

---

## [L4] design_gap — specclaw-verify-context fails on macOS with 'sed: 1: inva...

**When:** 2026-05-20 17:11 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
specclaw-verify-context fails on macOS with 'sed: 1: invalid command code f' — BSD sed incompatibility, blocks the verify pipeline on Darwin.

### Action
Audit specclaw-verify-context for sed -i / sed -E flag portability, similar to the v0.2.5 cross-platform sed fix. Follow-up change.

---

## [L5] design_gap — Spec did not specify behavior when spec.md already exists...

**When:** 2026-05-24 14:24 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
Spec did not specify behavior when spec.md already exists and /specclaw:plan is run without the flag (EC6 implied 'don't overwrite' but FR7 said 'behaves exactly as today')

### Action
Resolved in T3 by adding explicit 'if spec.md exists, skip spec step' branch in plan/SKILL.md; should be backported into spec.md FR7 wording on a future iteration

---

## [L6] agent_issue — specclaw-gh-sync create detects Issues disabled on the ta...

**When:** 2026-07-16 09:01 UTC
**Category:** agent_issue
**Priority:** medium
**Status:** pending

### Detail
specclaw-gh-sync create detects Issues disabled on the target repo and exits 0 with a skip warning, recording nothing in status.md. specclaw-validate-change plan/build gates then hard-fail (strict mode) on the missing 'GitHub Issue' line — a permanently unpassable gate while github.sync: true. Same condition treated as skip by one component, fatal by another.

### Action
validate-change should detect the issues-disabled condition, or gh-sync should record 'GitHub Issue: disabled' in status.md, so gates warn instead of block.

---
