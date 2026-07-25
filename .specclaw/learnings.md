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

## [L7] design_gap — yaml_get in specclaw-build-context does not strip inline ...

**When:** 2026-07-16 09:22 UTC
**Category:** design_gap
**Priority:** low
**Status:** pending

### Detail
yaml_get in specclaw-build-context does not strip inline YAML comments — commit_prefix renders as '"specclaw"       # Prefix for auto-commits' inside coding-agent payload commit instructions. yaml_val in validate-change already handles this; yaml_get predates it.

### Action
Port yaml_val's comment-stripping into yaml_get (or reuse yaml_val) in a lifecycle-bug-fixes follow-up change.

---

## [L8] design_gap — specclaw-browser-lock cmd_acquire writes $$ — the PID of ...

**When:** 2026-07-25 05:37 UTC
**Category:** design_gap
**Priority:** high
**Status:** pending

### Detail
specclaw-browser-lock cmd_acquire writes $$ — the PID of the short-lived browser-lock process itself — into the slot file, so slot_live() always sees a dead PID: 'status' reports 0/N while a slot is demonstrably held, and a concurrent acquire reclaims a live slot as stale. verify.playwright.max_browsers therefore does not gate concurrency for any subprocess caller (only for a caller that sources the script). Pre-existing since v0.5.9, found while wiring T9.

### Action
Follow-up change: record the caller's PID (or a heartbeat/flock) instead of $$, and add a concurrency test that two sequential acquires cannot both win the same slot

---

## [L9] design_gap — yaml_val strips a trailing single quote unconditionally a...

**When:** 2026-07-25 05:37 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
yaml_val strips a trailing single quote unconditionally after stripping double quotes, so any config value ending in ' — e.g. test_command: "sh -c 'npm test'" — is read back truncated and dies with 'unexpected EOF while looking for matching'. Pattern is duplicated across 6+ bin scripts.

### Action
Fix the quote-stripping to be paired-only, in one shared helper; add a parser test with a nested-quote command

---

## [L10] design_gap — specclaw-verify-context never forwards e2e evidence to th...

**When:** 2026-07-25 05:37 UTC
**Category:** design_gap
**Priority:** medium
**Status:** pending

### Detail
specclaw-verify-context never forwards e2e evidence to the verify agent: it maps only test_output/lint_output/build_output, and references/agent-prompts.md has no {{e2e_output}} placeholder. FR9's guarantee currently depends on the agent voluntarily re-reading collect output.

### Action
Add an {{e2e_output}}/e2e_state slot to specclaw-verify-context and agent-prompts.md — neither file is in this change's file map, so either extend T12 or open a follow-up

---
