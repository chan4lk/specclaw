# Tasks: Core records + plugin suggestions at the moment of need

**Change:** 059-core-records-suggest
**Created:** 2026-11-14
**Total Tasks:** 4

## Summary

Shared install check and the suggest script (tests first), then the lesson line, then the skill call sites,
then the version bump.

## Tasks

### Wave 1 — Scripts

- [x] `T1` — `lib/plugins.sh`, `specclaw-suggest`, `session-start` sourcing the lib, config template, suggest tests (AC-1…AC-5)
  - Files: plugins/specclaw/lib/plugins.sh, plugins/specclaw/bin/specclaw-suggest, plugins/specclaw/hooks/session-start, plugins/specclaw/templates/config.yaml, plugins/specclaw/tests/run-suggest-tests.sh, .github/workflows/ci.yml
  - Estimate: small
  - Kind: impl

- [x] `T2` — `lesson` line from `specclaw-log-learning`; `specclaw-timer` skips it quietly (AC-6)
  - Files: plugins/specclaw/bin/specclaw-log-learning, plugins/specclaw/bin/specclaw-timer, plugins/specclaw/tests/run-suggest-tests.sh
  - Estimate: small
  - Kind: impl

### Wave 2 — Call sites

- [x] `T3` — Five skill call sites, lean and full, plus docs (AC-7)
  - Files: plugins/specclaw/skills/verify/SKILL.md, plugins/specclaw/skills/status/SKILL.md, plugins/specclaw/skills/propose/SKILL.md, plugins/specclaw/skills/init/SKILL.md, plugins/specclaw/references/full/verify.md, plugins/specclaw/references/full/status.md, plugins/specclaw/references/full/propose.md, plugins/specclaw/references/full/init.md, plugins/specclaw/CLAUDE.md, plugins/specclaw/tests/run-suggest-tests.sh
  - Estimate: small
  - Kind: docs
  - Depends: T1

### Wave 3 — Ship

- [ ] `T4` — Bump all plugins to 0.9.7
  - Files: .claude-plugin/marketplace.json, plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json
  - Estimate: small
  - Kind: config
  - Depends: T3
