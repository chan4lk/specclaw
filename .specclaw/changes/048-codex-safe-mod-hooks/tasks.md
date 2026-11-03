# Tasks: Keep specclaw's hooks.json readable by Codex

**Change:** 048-codex-safe-mod-hooks
**Created:** 2026-11-03
**Total Tasks:** 3

## Summary

Split the hooks file, guard it with a test, then docs and version.

## Tasks

### Wave 1 — Fix

- [x] `T1` — Move `modules` to hooks/mod.json, name it in the Claude manifest, add the hooks.json key check (AC-1…AC-5)
  - Files: plugins/specclaw/hooks/hooks.json, plugins/specclaw/hooks/mod.json, plugins/specclaw/.claude-plugin/plugin.json, plugins/specclaw/tests/run-codex-plugin-tests.sh
  - Estimate: small
  - Kind: config

### Wave 2 — Ship

- [ ] `T2` — Docs name hooks/mod.json and the Codex reason (AC-6)
  - Files: plugins/specclaw/MOD.md, plugins/specclaw/CLAUDE.md, .specclaw/context.md
  - Estimate: small
  - Kind: docs
  - Depends: T1

- [ ] `T3` — Bump all plugins to 0.8.7
  - Files: .claude-plugin/marketplace.json, plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json
  - Estimate: small
  - Kind: config
  - Depends: T1
