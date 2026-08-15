# Tasks: Verification Engine

**Change:** verification-engine
**Created:** 2026-03-28
**Total Tasks:** 4

## Summary

Build the verification pipeline: evidence collection script, report template, SKILL.md verify flow, and verify agent prompt.

## Tasks

### Wave 1 — Infrastructure

- [x] `T1` — Create verify.sh for evidence collection and test execution
  - Files: skill/scripts/verify.sh
  - Estimate: medium
  - Notes: Subcommands: (1) collect <specclaw_dir> <change_name> — reads spec.md acceptance criteria, gathers list of changed files (from tasks.md file lists), reads current file contents (cap 200 lines each), runs test_command/lint_command/build_command from config if configured, outputs JSON with: acceptance_criteria (array), changed_files (array with contents), test_output, lint_output, build_output, tests_passed (bool), lint_passed (bool), build_passed (bool). (2) report <specclaw_dir> <change_name> — reads verify-report.md and outputs summary (verdict, pass/fail counts). (3) update-status <specclaw_dir> <change_name> <verdict> — updates status.md with verification result. Include --help, bash only.

- [x] `T2` — Create verify-report.md template and verify agent prompt template
  - Files: skill/templates/verify-report.md, skill/references/agent-prompts.md
  - Estimate: small
  - Notes: verify-report.md template with placeholders for change_name, date, model, verdict, criteria results, test output, issues, summary. For agent-prompts.md: the Verify Agent prompt already exists — review it and ensure it matches the report template format. If it needs updates, modify it. The prompt should instruct the agent to output EXACTLY the verify-report.md format so it can be saved directly.

### Wave 2 — Integration

- [x] `T3` — Update SKILL.md with detailed specclaw verify execution flow
  - Files: skill/SKILL.md
  - Depends: T1, T2
  - Estimate: medium
  - Notes: Replace the existing specclaw verify section with detailed steps: (1) Run verify.sh collect to gather evidence. (2) Build verify agent context from evidence + Verify Agent prompt template. (3) Spawn verify agent via sessions_spawn with models.review model. (4) Save agent output as verify-report.md in the change directory. (5) Run verify.sh update-status with the verdict. (6) Update STATUS.md dashboard. (7) If github.sync enabled, post results as issue comment. (8) If verdict is FAIL/PARTIAL, suggest remediation (re-plan failed criteria as new tasks). Include auto_verify hook — when automation.auto_verify is true, build flow triggers verify automatically.

- [x] `T4` — Create verify-context.sh for verify agent context construction
  - Files: skill/scripts/verify-context.sh
  - Depends: T1
  - Estimate: small
  - Notes: Similar to build-context.sh but for verification. Reads spec.md (full), verify.sh collect output (JSON evidence), and formats using Verify Agent prompt template from agent-prompts.md. Outputs complete context payload to stdout. Arguments: <specclaw_dir> <change_name>. Internally calls verify.sh collect to get evidence, then wraps in prompt template.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
