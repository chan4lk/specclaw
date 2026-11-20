# Tasks: An InfoSec agent for SpecClaw projects: before, during and after the build, with evals

**Change:** 069-infosec-agent
**Created:** 2026-11-16
**Total Tasks:** 9

## Summary

Write the agent, wire it into verify behind an off-by-default flag, guard it with a test, then bump the version. Then (2026-11-17) add the plan and build modes and wire them in, and the evals that score the agent.

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

### Wave 5 — Plan and build modes

- [x] `T6` — Give the agent three modes and test them (AC-6)
  - Files: plugins/specclaw/agents/infosec-reviewer.md, plugins/specclaw/tests/run-infosec-reviewer-tests.sh
  - Estimate: small
  - Kind: docs
  - Depends: T1, T3
  - Context: 33000
  - Notes: `mode` input; plan writes security-requirements.md with SR-n; build writes security/<T>.md; verify also reports each SR-n. New required items in the test, each with a deleted-item mutant.

- [x] `T7` — Wire the modes into plan, build and verify (AC-7, AC-8, AC-9)
  - Files: plugins/specclaw/references/full/plan.md, plugins/specclaw/references/full/build.md, plugins/specclaw/references/full/verify.md, plugins/specclaw/tests/run-infosec-reviewer-tests.sh
  - Estimate: medium
  - Kind: config
  - Depends: T6
  - Context: 50000
  - Notes: all behind workflow.security_review; plan step before spec.md; build step beside 2b, entry-point tasks only, reuses `specclaw-build review-package`; verify 3.52 passes security-requirements.md and counts unmet SR-n. AC-3 test stays scoped to the Step 3.52 section.

### Wave 6 — Evals

- [x] `T8` — Write the eval cases and their structural test; register in CI (AC-10, AC-11)
  - Files: plugins/specclaw/tests/evals/infosec, plugins/specclaw/tests/run-infosec-eval-cases-tests.sh, .github/workflows/ci.yml
  - Estimate: medium
  - Kind: test
  - Depends: T1
  - Context: 45000
  - Notes: 8 cases from the Shannon findings, each vulnerable + fixed + `expect: rule: <id>`; the test checks the pair, a non-empty expect and that the rule id exists in a review pack; one mutant per kind of break, reported by case name.

- [x] `T9` — Write the eval runner and the nightly workflow (AC-12, AC-13)
  - Files: plugins/specclaw/tests/run-infosec-evals.sh, .github/workflows/infosec-evals.yml
  - Estimate: medium
  - Kind: test
  - Depends: T6, T8
  - Context: 38000
  - Notes: copies the opt-in, reps, model-recorded shape of run-trigger-tests.sh; prints catch rate and false-alarm rate; skip line and exit 0 without SPECCLAW_INFOSEC_EVALS=1.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
