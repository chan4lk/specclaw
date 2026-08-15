# Tasks: Build Error Journal

**Change:** build-error-journal
**Created:** 2026-03-28
**Total Tasks:** 3

## Summary

Create the error logging script and template, modify build-context.sh to inject error history, update SKILL.md build flow.

## Tasks

### Wave 1 — Error logging infrastructure

- [x] `T1` — Create log-error.sh and errors.md template
  - Files: skill/scripts/log-error.sh, skill/templates/errors.md
  - Estimate: small
  - Notes: log-error.sh accepts: <specclaw_dir> <change_name> <task_id> <wave> <agent_label> <summary> [--error-file <path>]. Appends structured entry to errors.md (creates with template header if missing). --resolve <task_id> marks all entries for that task as resolved_on_retry. Cap error output at 50 lines. Include --help. Must be executable.

### Wave 2 — Integration with build pipeline

- [x] `T2` — Modify build-context.sh to inject previous errors on retry
  - Files: skill/scripts/build-context.sh
  - Depends: T1
  - Estimate: small
  - Notes: After building the main context, check if errors.md exists and has entries for the current task_id. If so, extract the last 3 entries for that task and append as a "## Previous Errors for This Task" section in the context payload. Include a note: "Avoid repeating these mistakes."

- [x] `T3` — Update SKILL.md build flow with error logging steps
  - Files: skill/SKILL.md
  - Depends: T1
  - Estimate: small
  - Notes: In the build command section, add: (1) On task failure, call log-error.sh with the failure details. (2) On task success after previous failure, call log-error.sh --resolve. (3) Mention errors.md in the directory structure section. Keep changes minimal — just add the error logging hooks to the existing build flow.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
