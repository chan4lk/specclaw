# Tasks: Core guards (branch, done) and the PR size cap

**Change:** 060-core-guards-size-cap
**Created:** 2026-11-14
**Total Tasks:** 4

## Summary

Three guards, each test first, then docs and the version bump.

## Tasks

### Wave 1 — Guards

- [ ] `T1` — Branch guard in the mod's propose gate (AC-1, AC-2)
  - Files: plugins/specclaw/hooks/core/gate.ts, plugins/specclaw/hooks/branch.ts, plugins/specclaw/hooks/register.tsx, plugins/specclaw/tests/gate.spec.ts, plugins/specclaw/tests/branch.test.ts
  - Estimate: medium
  - Kind: impl

- [ ] `T2` — Done guard Stop hook, registered for Claude Code only (AC-3, AC-5)
  - Files: plugins/specclaw/hooks/done-guard, plugins/specclaw/hooks/mod.json, plugins/specclaw/lib/base-ref.sh, plugins/specclaw/tests/run-done-guard-tests.sh, plugins/specclaw/tests/run-codex-plugin-tests.sh
  - Estimate: medium
  - Kind: impl

- [ ] `T3` — Size cap in specclaw-verify with the pr.size_cap key (AC-4)
  - Files: plugins/specclaw/bin/specclaw-verify, plugins/specclaw/lib/base-ref.sh, plugins/specclaw/templates/config.yaml, plugins/specclaw/tests/run-size-cap-tests.sh
  - Estimate: medium
  - Kind: impl

### Wave 2 — Ship

- [ ] `T4` — Docs, verify flow step and CI registration (AC-6)
  - Files: plugins/specclaw/MOD.md, plugins/specclaw/CLAUDE.md, plugins/specclaw/skills/verify/SKILL.md, plugins/specclaw/references/full/verify.md, .github/workflows/ci.yml
  - Estimate: small
  - Kind: docs
  - Depends: T1, T2, T3
