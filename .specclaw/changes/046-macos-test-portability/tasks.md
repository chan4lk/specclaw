# Tasks: macOS test portability

**Change:** 046-macos-test-portability
**Created:** 2026-10-20
**Total Tasks:** 3

## Summary

Fix two bin portability bugs, then the test-only GNU-isms, then bump.

## Tasks

### Wave 1 — Product bugs

- [x] `T1` — Unpadded wc count in run-long; timeout fallback in browser-lock probe (AC-1)
  - Files: plugins/specclaw/bin/specclaw-run-long, plugins/specclaw/bin/specclaw-browser-lock, plugins/specclaw/tests/run-long-orchestration-tests.sh
  - Estimate: small
  - Kind: impl

### Wave 2 — Test portability

- [ ] `T2` — Portable find/stat/sed/timeout/wc in parser, change-numbering, phase-state, synth-agent suites (AC-2..AC-5)
  - Files: plugins/specclaw/tests/run-parser-tests.sh, plugins/specclaw/tests/run-change-numbering-tests.sh, plugins/specclaw/tests/run-phase-state-tests.sh, plugins/specclaw/tests/run-synth-agent-tests.sh
  - Estimate: small
  - Kind: test
- [ ] `T3` — Bump plugin versions
  - Files: plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Kind: config
  - Depends: T1, T2
