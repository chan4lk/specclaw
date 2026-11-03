# Tasks: Project-local custom presets

**Change:** 045-project-custom-presets
**Created:** 2026-10-19
**Total Tasks:** 3

## Summary

Resolver bin, wire build/init to it, version bump.

## Tasks

### Wave 1 — Resolver

- [x] `T1` — `specclaw-presets` resolver with local precedence, `Extends:`, unknown-name handling (AC-1..AC-5)
  - Files: plugins/specclaw/bin/specclaw-presets, plugins/specclaw/tests/run-preset-check-tests.sh
  - Estimate: small
  - Kind: impl

### Wave 2 — Wiring

- [x] `T2` — Build reads resolver output; init scaffolds `presets/README.md` and lists local presets (AC-6, AC-7)
  - Files: plugins/specclaw/skills/build/SKILL.md, plugins/specclaw/skills/init/SKILL.md, plugins/specclaw/bin/specclaw-init, plugins/specclaw/templates/presets-README.md, plugins/specclaw/tests/run-preset-check-tests.sh
  - Estimate: small
  - Kind: impl
  - Depends: T1
- [x] `T3` — Bump plugin version
  - Files: plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T2
