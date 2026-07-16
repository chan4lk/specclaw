# Tasks: Prompt Hardening — Evidence-Grounded Agent Payloads

**Change:** prompt-hardening
**Created:** 2026-07-16
**Total Tasks:** 6

## Summary

Five independent text surfaces harden in parallel (Wave 1 — different files, no cross-dependencies), then release plumbing last so docs describe the finished state.

## Tasks

### Wave 1 — Hardening blocks (parallel, independent files)

- [x] `T1` — Build payload: reorder + hardening blocks
  - Files: plugins/specclaw/bin/specclaw-build-context
  - Estimate: medium
  - Depends: —
  - Notes: FR2 investigate-before-answering, FR3 anti-reward-hacking, FR9 temp-file cleanup as delimited blocks before the task section. FR4 reorder: move Your Task / Files to Modify / Constraints / Definition of Done to payload end, after spec/design/existing-code content; guardrails stay first. FR5: add one-line whys to the scope constraint (parallel tasks own other files; out-of-list edits auto-log design_gap) and test constraint (verify gate consumes the evidence). Keep --failure-record/--reflection append behavior intact.

- [x] `T2` — Verify payload: quote-first verdicts
  - Files: plugins/specclaw/bin/specclaw-verify-context
  - Estimate: small
  - Depends: —
  - Notes: FR1 — instruction appended with the template: before any verdict, extract exact quotes (AC line, code line, test output) into a quotes section; verdicts must reference those quotes; unquotable claims are not evidence.

- [x] `T3` — agent-prompts.md: ordering mirror + few-shot examples
  - Files: plugins/specclaw/references/agent-prompts.md
  - Estimate: medium
  - Depends: —
  - Notes: FR6 — add `<example>`-tagged pairs: one good reviewer finding (file:line, quoted code, concrete fix) vs one bad (vague, unquoted); one strong AC (testable, specific) vs one weak. Note the task-last ordering convention where templates describe payload assembly.

- [x] `T4` — Agents: quoted evidence + research directive
  - Files: plugins/specclaw/agents/code-reviewer.md, plugins/specclaw/agents/spec-author.md
  - Estimate: small
  - Depends: —
  - Notes: code-reviewer: every finding must quote the exact line(s) it flags; findings without quotable evidence are dropped (FR1). spec-author: FR8 structured-research directive — competing hypotheses, confidence tracking, self-critique before finalizing sections.

- [x] `T5` — Skills: reversibility + calibration lines
  - Files: plugins/specclaw/skills/loop/SKILL.md, plugins/specclaw/skills/build/SKILL.md
  - Estimate: small
  - Depends: —
  - Notes: loop: FR7 confirm-or-avoid list (destructive ops, hard-to-reverse, externally visible; never bypass safety checks like --no-verify to green a gate). build: FR9 subagent-vs-direct calibration note (parallel/isolated → subagent; sequential/single-file/shared-context → direct).

### Wave 2 — Release plumbing

- [x] `T6` — README, CHANGELOG, version 0.5.1
  - Files: README.md, CHANGELOG.md, plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Depends: T1, T2, T3, T4, T5
  - Notes: README: short "Evidence-grounded agent payloads" note under the workflow/architecture docs. CHANGELOG 0.5.2 entry citing the hardening blocks. Version 0.5.1 both files, in sync.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:** see the tasks above for the live shape — checkbox, ID, title, then `Files / Estimate / Depends / Notes` sub-bullets.
