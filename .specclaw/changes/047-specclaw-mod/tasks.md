# Tasks: specclaw mod

**Change:** 047-specclaw-mod
**Created:** 2026-11-02
**Total Tasks:** 5

## Summary

Pure core with tests first, then the mod wiring, then packaging and CI.

## Tasks

### Wave 1 — Core

- [ ] `T1` — Pure core + bun tests for reader, active/current, pane/band/status text, gate decision (AC-1…AC-7)
  - Files: plugins/specclaw-mod/hooks/core.ts, plugins/specclaw-mod/tests/core.test.ts, plugins/specclaw-mod/tests/run-mod-tests.sh
  - Estimate: medium
  - Kind: impl
  - Notes: tests use in-memory fixtures (file map + mtimes), not the real repo.

### Wave 2 — Mod

- [ ] `T2` — Mod wiring: manifest, hooks.json, types contract, register.tsx (pane, band, status, command, gate) (FR-3…FR-8, AC-8)
  - Files: plugins/specclaw-mod/.claude-plugin/plugin.json, plugins/specclaw-mod/hooks/hooks.json, plugins/specclaw-mod/hooks/register.tsx, plugins/specclaw-mod/types/index.d.ts, plugins/specclaw-mod/tsconfig.json
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: `claude plugin validate` + `tsc` clean.

### Wave 3 — Ship

- [ ] `T3` — Marketplace entry + version bump to 0.8.5 across all plugins (AC-9)
  - Files: .claude-plugin/marketplace.json, plugins/*/.claude-plugin/plugin.json
  - Estimate: small
  - Kind: config
  - Depends: T2

- [ ] `T4` — CI registration of run-mod-tests.sh with setup-bun (AC-10)
  - Files: .github/workflows/ci.yml
  - Estimate: small
  - Kind: config
  - Depends: T1

- [ ] `T5` — Docs: plugin README + root README line
  - Files: plugins/specclaw-mod/README.md, README.md
  - Estimate: small
  - Kind: docs
  - Depends: T2
