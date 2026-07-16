# Tasks: Smart Base Branch Detection

**Change:** smart-base-branch
**Created:** 2026-07-16
**Total Tasks:** 4

## Summary

Both script edits are independent (same helper duplicated per repo convention) and run as Wave 1; fixture tests exercise both in Wave 2; release plumbing last.

## Tasks

### Wave 1 — Script changes (parallel)

- [ ] `T1` — specclaw-build: helper + base-aware setup/finalize
  - Files: plugins/specclaw/bin/specclaw-build
  - Estimate: medium
  - Depends: —
  - Notes: Add detect_base_branch() per design.md. Setup: fetch base (warn-only), new branches start from origin/<base> when the ref verifies, else local <base>, else HEAD+warning; divergence warning when creating while HEAD isn't the base tip; resume path untouched; add "base_branch" to setup JSON. Finalize: replace main/master guess, checkout detected base before merge. Quote every branch expansion (slashed names).

- [ ] `T2` — specclaw-pr: helper + dynamic --base
  - Files: plugins/specclaw/bin/specclaw-pr
  - Estimate: small
  - Depends: —
  - Notes: Add the same helper; replace hardcoded `gh pr create --base main` with detected value; version-bump comparison uses the same variable (drop its inline detection).

### Wave 2 — Tests + config

- [ ] `T3` — Fixture tests + config key
  - Files: plugins/specclaw/tests/run-parser-tests.sh, plugins/specclaw/templates/config.yaml
  - Estimate: medium
  - Depends: T1, T2
  - Notes: Case 7: build a local bare origin with default branch `develop`, clone, init .specclaw. Assert: detection echoes develop (AC1); config override `release/1.0` wins (AC2); no-remote fallback to main (AC3); setup from a side branch starts the change branch at origin/develop tip + divergence warning (AC4); resume unchanged (AC5). Helper invoked via `bash -c 'source-free' `— call the script functions by running setup and inspecting JSON/behavior, or grep-assert the pr script's --base usage (AC6). Add commented `base_branch: ""` under git: in templates/config.yaml.

### Wave 3 — Release plumbing

- [ ] `T4` — README, CHANGELOG, version 0.5.3
  - Files: README.md, CHANGELOG.md, plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Depends: T1, T2, T3
  - Notes: README config example gains base_branch with a sentence on the detection chain. CHANGELOG 0.5.3 entry. Version both files, in sync.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:** see the tasks above for the live shape — checkbox, ID, title, then `Files / Estimate / Depends / Notes` sub-bullets.
