# Verification Report: 040-codex-skill-packaging

**Verified:** 2026-09-20
**Verdict:** PARTIAL

## Evidence

- `bash plugins/specclaw/tests/run-codex-skill-tests.sh` — PASS; 35 canonical targets and no copied asset trees.
- `bash plugins/specclaw/tests/shellcheck-gate.sh` — exit 0; no new findings.
- `bash plugins/specclaw/tests/run-description-lint-tests.sh` — exit 0; no new offences.
- `git diff --exit-code 4fd3a51..HEAD -- .claude-plugin/marketplace.json plugins/specclaw/.claude-plugin/plugin.json plugins/specclaw/skills` — exit 0.
- `.github/workflows/ci.yml` invokes `bash plugins/specclaw/tests/run-codex-skill-tests.sh`.
- `git diff --check 4fd3a51..HEAD` — clean.

## Acceptance Criteria

| AC | Verdict | Evidence |
|---|---|---|
| AC1 | PASS | `.agents/skills/specclaw/SKILL.md` exists with `name: specclaw` and a non-empty description. |
| AC2 | PASS | The adapter resolves the Git repository root, derives `plugins/specclaw`, dynamically routes `skills/<verb>/SKILL.md`, and rejects an absent verb directory. |
| AC3 | PASS | The adapter directs helpers to `$SPECCLAW_PLUGIN_ROOT/bin/`; the adapter directory contains only `SKILL.md`, with no copied skills, binaries, templates, or references. |
| AC4 | PASS | The adapter explicitly maps `CLAUDE_PLUGIN_ROOT` resource references to `$SPECCLAW_PLUGIN_ROOT`. |
| AC5 | PASS | The change has no diff in the marketplace manifest, Claude plugin manifest, or canonical Claude skill documents. |
| AC6 | PARTIAL | The focused validation passes locally and is registered in CI, but that validator does not inspect the CI workflow. It cannot detect removal of its own CI registration. |
| AC7 | PASS | README, site documentation, and contributor guidance document checkout-local Codex discovery and `$specclaw`, retain the Claude install commands, and state that no global Codex skill is installed. |

## Required Remediation

Extend `plugins/specclaw/tests/run-codex-skill-tests.sh` to assert that
`.github/workflows/ci.yml` invokes the suite. Strengthen the suite to enforce
the root/verb-resolution and protected-Claude-asset invariants it is intended
to guard, then rerun verification.
