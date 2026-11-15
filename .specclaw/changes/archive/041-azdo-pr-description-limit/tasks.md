# Tasks: Keep Azure DevOps PR descriptions under the 4,000-character limit

**Change:** 041-azdo-pr-description-limit
**Created:** 2026-09-27
**Total Tasks:** 3

## Summary

Capture a golden of today's output, add a character budget with priority-ordered truncation to `build_pr_description()`, cover it with a registered test suite, bump the version.

## Tasks

### Wave 1 — Test first

- [x] `T1` — Write `run-azdo-pr-description-tests.sh` with fixtures and a golden of the *current* small-input output (AC3), plus failing cases for AC1, AC2, AC4, AC5, AC6; register in ci.yml (AC7)
  - Files: plugins/specclaw/tests/run-azdo-pr-description-tests.sh, plugins/specclaw/tests/fixtures/azdo-pr-description/, .github/workflows/ci.yml
  - Estimate: medium
  - Kind: test
  - Notes: extract functions from bin/specclaw-azdo-pr via awk; set CHANGE_DIR/CHANGE_NAME/CONFIG_FILE/SCRIPT_DIR in the test. Capture the golden BEFORE T2 touches the script.

### Wave 2 — Implement

- [x] `T2` — Implement budget read + `fit_description` + section refactor in `build_pr_description()`; add commented `pr_description_max` to config template
  - Files: plugins/specclaw/bin/specclaw-azdo-pr, plugins/specclaw/templates/config.yaml
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: FR1–FR7. All T1 cases green; shellcheck gate unchanged.

### Wave 3 — Release

- [x] `T3` — Bump patch version 0.7.7 → 0.7.8 in the three version files (separate commit)
  - Files: plugins/specclaw/.claude-plugin/plugin.json, plugins/specclaw/.codex-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T2

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
