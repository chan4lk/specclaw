# Tasks: pr-command

## Tasks

### Wave 1 (no dependencies)

- [x] `T1` — Add `pr` phase to validate-change.sh
  - Files: `skill/scripts/validate-change.sh`
  - Estimate: small
  - Add case `pr)` in the phase switch: check verify-report.md exists; idempotency guard checks for existing PR URL in status.md

- [x] `T2` — Create pr.sh skeleton with helpers
  - Files: `skill/scripts/pr.sh`
  - Estimate: small
  - Script header, usage(), die()/warn()/fail() helpers, yaml_val() (copy from gh-sync.sh), arg parsing, STRICT mode detection. No business logic yet — just the scaffolding.

### Wave 2 (depends on Wave 1)

- [x] `T3` — Implement test policy prompt and config write
  - Files: `skill/scripts/pr.sh`
  - Depends: T2
  - Estimate: small
  - check_test_policy(): read pr.test_policy from config; if absent, prompt stdin loop (validate none|unit|e2e|both), then yaml_set_pr_policy() to write to config.yaml using append-or-sed strategy

- [x] `T4` — Implement test policy enforcement
  - Files: `skill/scripts/pr.sh`
  - Depends: T2
  - Estimate: small
  - enforce_test_policy(): skip if none; check build.test_command non-empty; grep verify-report.md for test evidence keywords (test|passed|failed|coverage|e2e|unit|assert); collect failures; report per STRICT mode

### Wave 3 (depends on Wave 2)

- [x] `T5` — Implement PR body builder, title extractor, gh pr create, URL save
  - Files: `skill/scripts/pr.sh`
  - Depends: T3, T4
  - Estimate: medium
  - build_pr_title(): scan proposal.md for first content line, format "[specclaw] <change>: <summary>", truncate 72 chars
  - build_pr_body(): assemble all sections (Summary, Acceptance Criteria, Verification, Tests, Closes #N, footer)
  - main(): call validate → check_test_policy → enforce_test_policy → build title/body → gh pr create → save URL to status.md

### Wave 4 (depends on Wave 3)

- [x] `T6` — Add `specclaw pr` section to SKILL.md
  - Files: `skill/SKILL.md`
  - Depends: T5
  - Estimate: small
  - Insert section after `specclaw verify` block (before `specclaw status`) documenting the command trigger, steps, and script invocation

- [x] `T7` — Add `pr.test_policy` field to templates/config.yaml
  - Files: `skill/templates/config.yaml`
  - Depends: T5
  - Estimate: small
  - Append `pr:` section with `test_policy: ""` and explanatory comments at end of file
