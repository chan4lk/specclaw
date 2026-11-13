# Tasks: Security rules in the presets

**Change:** 059-preset-security-rules
**Created:** 2026-11-12
**Total Tasks:** 6

## Summary

Add a `## Security` section to the base preset with a test that guards it, bump the version, then add
stack-specific Security sections to the five stack presets and guard them with a test, then add matching
security rules to the review rule packs and guard those with a test.

## Tasks

### Wave 1 — Base security section

- [x] `T1` — Add `## Security` to base.md and a test for it (AC-1, AC-2, AC-3)
  - Files: plugins/specclaw/presets/base.md, plugins/specclaw/tests/run-preset-check-tests.sh
  - Estimate: small
  - Kind: docs
  - Notes: eight bold-keyword bullets; keep base.md ≤ 60 lines; test names any missing keyword.

### Wave 2 — Release

- [x] `T2` — Patch-bump every plugin and marketplace version
  - Files: plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T1
  - Notes: all versions stay equal (review rule R1); separate commit `chore: bump version to X.Y.Z`.

### Wave 3 — Stack preset rules

- [x] `T3` — Add `## Security` to dotnet.md, python.md, node.md, nextjs.md and react-spa.md (AC-4)
  - Files: plugins/specclaw/presets/dotnet.md, plugins/specclaw/presets/python.md, plugins/specclaw/presets/node.md, plugins/specclaw/presets/nextjs.md, plugins/specclaw/presets/react-spa.md
  - Estimate: small
  - Kind: docs
  - Depends: T1
  - Notes: only the rules listed in spec.md; no repeats of base.md; each file ≤ 60 lines.

### Wave 4 — Stack test

- [x] `T4` — Test that each stack preset keeps its Security rules (AC-2, AC-5)
  - Files: plugins/specclaw/tests/run-preset-check-tests.sh
  - Estimate: small
  - Kind: test
  - Depends: T1, T3
  - Notes: reuse the T1 helper; one case per stack plus deleted-rule mutants that name stack and keyword.

### Wave 5 — Review rule packs

- [x] `T5` — Add security rules to the six specclaw-review rule packs (AC-6)
  - Files: plugins/specclaw-review/review-rules/base.md, plugins/specclaw-review/review-rules/dotnet.md, plugins/specclaw-review/review-rules/python.md, plugins/specclaw-review/review-rules/node.md, plugins/specclaw-review/review-rules/nextjs.md, plugins/specclaw-review/review-rules/react-spa.md
  - Estimate: small
  - Kind: docs
  - Depends: T3
  - Notes: only the ids listed in spec.md; each with a severity; none repeat B8, DN5, ND3, PY4, RS4, NX1, NX2.

### Wave 6 — Review pack test

- [x] `T6` — Test that each review pack keeps its security rules (AC-7)
  - Files: plugins/specclaw-review/tests/run-review-tests.sh
  - Estimate: small
  - Kind: test
  - Depends: T5
  - Notes: one presence check per pack plus a deleted-rule mutant per id, reported by id.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
