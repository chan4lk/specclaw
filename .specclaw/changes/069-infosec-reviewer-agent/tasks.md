# Tasks: An InfoSec reviewer agent for SpecClaw projects

**Change:** 069-infosec-reviewer-agent
**Created:** 2026-11-16
**Total Tasks:** 5

## Summary

Write the agent, wire it into verify behind an off-by-default flag, guard it with a test, then bump the version.

## Tasks

### Wave 1 — Agent and wiring

- [x] `T1` — Write `agents/infosec-reviewer.md` (AC-1)
  - Files: plugins/specclaw/agents/infosec-reviewer.md
  - Estimate: small
  - Kind: docs
  - Notes: shape of code-reviewer.md; four steps; five SpecClaw-specific checks; evidence discipline.

- [x] `T2` — Add `workflow.security_review` and the verify step (AC-2, AC-3)
  - Files: plugins/specclaw/templates/config.yaml, plugins/specclaw/references/full/verify.md
  - Estimate: small
  - Kind: config
  - Depends: T1
  - Notes: default false; advisory; step sits after Step 3.5.

### Wave 2 — Test

- [x] `T3` — Test the agent, config key and verify step; register in CI (AC-4, AC-5)
  - Files: plugins/specclaw/tests/run-infosec-reviewer-tests.sh, .github/workflows/ci.yml
  - Estimate: small
  - Kind: test
  - Depends: T1, T2
  - Notes: one deleted-item mutant per required item, reported by name.

### Wave 3 — Release

- [x] `T4` — Patch-bump every plugin and marketplace version
  - Files: plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T3
  - Notes: all versions stay equal; separate commit `chore: bump version to X.Y.Z`. Shared with change 068 in one PR: its single bump commit covers both.

### Wave 4 — Auth-flow questions

- [x] `T5` — Add the auth-flow questions to the agent and its test (AC-1, AC-4)
  - Files: plugins/specclaw/agents/infosec-reviewer.md, plugins/specclaw/tests/run-infosec-reviewer-tests.sh
  - Estimate: small
  - Kind: docs
  - Depends: T1, T3
  - Notes: six attacker questions under step 2; one more required item in the test, with its deleted-item mutant.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
