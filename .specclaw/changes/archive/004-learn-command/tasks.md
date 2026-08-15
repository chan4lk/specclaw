# Tasks: specclaw learn

**Change:** learn-command
**Created:** 2026-03-28
**Total Tasks:** 2

## Summary

Create the learning logging script + template, update SKILL.md.

## Tasks

### Wave 1 — Script and template

- [x] `T1` — Create log-learning.sh and learnings.md template
  - Files: skill/scripts/log-learning.sh, skill/templates/learnings.md
  - Estimate: medium
  - Notes: log-learning.sh modes: (1) Log: `log-learning.sh <specclaw_dir> <change> <category> <priority> "<detail>" ["<action>"]` — categories: spec_gap|design_gap|pattern|best_practice|agent_issue, priorities: low|medium|high. Auto-creates learnings.md from template if missing. Sequential IDs (L1, L2...). (2) List: `log-learning.sh <specclaw_dir> <change> --list` — shows all entries with ID, category, priority, status, one-liner. (3) Promote: `log-learning.sh <specclaw_dir> <change> --promote <id>` — marks entry as promoted. Include --help, set -euo pipefail, executable.

### Wave 2 — SKILL.md integration

- [x] `T2` — Add specclaw learn command to SKILL.md
  - Files: skill/SKILL.md
  - Depends: T1
  - Estimate: small
  - Notes: Add a new ### specclaw learn section after the build section. Document: trigger patterns ("specclaw learn", "log a learning", "what did we learn"), the three modes (log, list, promote), and how learnings feed into pattern detection. Keep it concise — match style of other command sections.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
