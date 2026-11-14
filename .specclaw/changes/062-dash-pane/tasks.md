# Tasks: specclaw-dash — one read-only pane for the loops and token use

**Change:** 062-dash-pane
**Created:** 2026-11-14
**Total Tasks:** 4

## Summary

Pure logic first, test first (scanner, loops, view), then the mod wiring and its kit test, then packaging,
then the 059 follow-up for `dash`.

## Tasks

### Wave 1 — Pure logic

- [x] `T1` — Transcript scanner and the loops/view functions with bun specs over fixtures (AC-2, AC-3, AC-4, AC-5)
  - Files: plugins/specclaw-dash/hooks/core/scan.ts, plugins/specclaw-dash/hooks/core/loops.ts, plugins/specclaw-dash/hooks/core/view.ts, plugins/specclaw-dash/types/index.d.ts, plugins/specclaw-dash/tests/scan.spec.ts, plugins/specclaw-dash/tests/loops.spec.ts, plugins/specclaw-dash/tests/view.spec.ts, plugins/specclaw-dash/tests/fixtures.ts
  - Estimate: large
  - Kind: impl

### Wave 2 — Mod and packaging

- [x] `T2` — Mod: `/dash`, pane, band, status line, refresh, reads through `$.fs`/`$.env`/`$.mcp`; kit test (AC-5, AC-6, AC-7)
  - Files: plugins/specclaw-dash/.claude-plugin/plugin.json, plugins/specclaw-dash/hooks/mod.json, plugins/specclaw-dash/hooks/register.tsx, plugins/specclaw-dash/hooks/read.ts, plugins/specclaw-dash/tests/pane.test.tsx, plugins/specclaw-dash/tests/run-mod-tests.sh
  - Estimate: medium
  - Kind: impl
  - Depends: T1
- [ ] `T3` — Packaging: marketplace entry, README row and plugin README, CI step, split test knows dash is Claude-only (AC-1)
  - Files: .claude-plugin/marketplace.json, README.md, plugins/specclaw-dash/README.md, .github/workflows/ci.yml, plugins/specclaw/tests/run-plugin-split-tests.sh
  - Estimate: small
  - Kind: config
  - Depends: T2

### Wave 3 — 059 follow-up

- [ ] `T4` — `dash` feature row, install check by folder, status-skill call sites, suggest tests (AC-8)
  - Files: plugins/specclaw/lib/plugins.sh, plugins/specclaw/bin/specclaw-suggest, plugins/specclaw/skills/status/SKILL.md, plugins/specclaw/references/full/status.md, plugins/specclaw/tests/run-suggest-tests.sh
  - Estimate: small
  - Kind: impl
