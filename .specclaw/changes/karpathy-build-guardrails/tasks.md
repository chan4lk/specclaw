# Tasks: Adopt Karpathy CLAUDE.md guardrails for build (and adjacent phases)

**Change:** karpathy-build-guardrails
**Created:** 2026-05-20
**Total Tasks:** 6

## Summary

Six tasks across three waves. Wave 1 lands the vendored reference file (no
dependencies). Wave 2 wires it into the build pipeline and updates the three
skill docs in parallel (all depend on the reference existing). Wave 3 bumps
the version and updates CHANGELOG (depends on everything else being final, so
the release notes are accurate).

## Tasks

### Wave 1 — Vendor the reference

- [x] `T1` — Create `agent-guardrails.md` reference with verbatim Karpathy rules
  - Files: `plugins/specclaw/references/agent-guardrails.md`
  - Estimate: small
  - Depends: —
  - Notes: Vendor the four rules from https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md verbatim. Add a header noting upstream source + commit SHA + license (confirm MIT during this task — if upstream license differs, stop and surface). Add a brief "How specclaw uses this" footer that ties rule 3 to the task's declared `files:` list and rule 4 to spec acceptance criteria. Keep total under 100 lines.

### Wave 2 — Wire it in (parallel)

- [x] `T2` — Inject guardrails into `specclaw-build-context` prompt
  - Files: `plugins/specclaw/bin/specclaw-build-context`
  - Estimate: small
  - Depends: T1
  - Notes: Add `GUARDRAILS_FILE="$SCRIPT_DIR/../references/agent-guardrails.md"` near other path resolutions. Read into `GUARDRAILS_CONTENT` (warn-to-stderr and set empty on missing file — do NOT abort). Build a `GUARDRAILS_SECTION` string that contains `## Agent Guardrails\n${GUARDRAILS_CONTENT}\n` only when content is non-empty; otherwise empty string (so the section disappears cleanly). Insert `${GUARDRAILS_SECTION}` in the final heredoc immediately before `## Your Task`. Run `bash -n` on the file before declaring done.

- [x] `T3` — Update `skills/build/SKILL.md` with guardrails reference
  - Files: `plugins/specclaw/skills/build/SKILL.md`
  - Estimate: small
  - Depends: T1
  - Notes: Add a new bullet to the "Key Principles" section: "**Agent guardrails** — every coding agent is auto-prepended Karpathy's four behavioral rules (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution). See `references/agent-guardrails.md`." Do not restructure surrounding content.

- [x] `T4` — Update `skills/plan/SKILL.md` to cite rules 1 & 2
  - Files: `plugins/specclaw/skills/plan/SKILL.md`
  - Estimate: small
  - Depends: T1
  - Notes: Add a single short note near the task-generation step reminding the planner to apply rule 1 (state assumptions, ask if unclear) and rule 2 (no speculative tasks / no over-decomposition). Link to `references/agent-guardrails.md`. One paragraph max.

- [x] `T5` — Update `skills/verify/SKILL.md` to cite rule 4
  - Files: `plugins/specclaw/skills/verify/SKILL.md`
  - Estimate: small
  - Depends: T1
  - Notes: Add a single short note framing the verify phase as rule 4's goal-check loop — i.e. each spec acceptance criterion is the success criterion. Link to `references/agent-guardrails.md`. One sentence or short paragraph.

### Wave 3 — Release plumbing

- [x] `T6` — Bump version to 0.4.0 and add CHANGELOG entry
  - Files: `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`
  - Estimate: small
  - Depends: T2, T3, T4, T5
  - Notes: Change `"version": "0.3.3"` to `"0.4.0"` in both JSON files (the marketplace entry for the `specclaw` plugin). Add `## [0.4.0] — 2026-05-20` to CHANGELOG.md above the `0.3.3` entry; describe the additions: new agent-guardrails reference, build-context injection, skill doc updates. Match the style of the existing CHANGELOG entries.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:** see the tasks above for the live shape — checkbox, ID, title, then `Files / Estimate / Depends / Notes` sub-bullets.
