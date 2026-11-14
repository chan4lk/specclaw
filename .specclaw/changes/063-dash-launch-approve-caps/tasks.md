# Tasks: specclaw-dash actions — launch, approve lessons, caps, dismissed

**Change:** 063-dash-launch-approve-caps
**Created:** 2026-11-14
**Total Tasks:** 3

## Summary

The two missing CLI verbs first, then the pure action mapping with specs, then the pane wiring with kit tests
and docs.

## Tasks

### Wave 1 — Commands and mapping

- [ ] `T1` — `specclaw-review learn --reject` and `specclaw-suggest --dismissed/--undismiss`, with tests (AC-6, AC-7)
  - Files: plugins/specclaw-review/bin/specclaw-review, plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/lib/review_memory.py, plugins/specclaw-review/tests/run-review-tests.sh, plugins/specclaw/bin/specclaw-suggest, plugins/specclaw/tests/run-suggest-tests.sh
  - Estimate: small
  - Kind: impl
- [ ] `T2` — Pure action mapping: commands, value patterns, dry-run/caps/dismissed/rules parsers, change approval and feature; bun specs (AC-1, AC-2)
  - Files: plugins/specclaw-dash/hooks/core/actions.ts, plugins/specclaw-dash/hooks/core/loops.ts, plugins/specclaw-dash/types/index.d.ts, plugins/specclaw-dash/tests/actions.spec.ts, plugins/specclaw-dash/tests/loops.spec.ts
  - Estimate: medium
  - Kind: impl

### Wave 2 — Pane

- [ ] `T3` — Runner and ACTIONS part: buttons, inputs, confirm, prompt fallback; kit tests; AC-8 grep; README and manifests (AC-3, AC-4, AC-5, AC-8)
  - Files: plugins/specclaw-dash/hooks/act.ts, plugins/specclaw-dash/hooks/register.tsx, plugins/specclaw-dash/hooks/read.ts, plugins/specclaw-dash/hooks/core/view.ts, plugins/specclaw-dash/tests/pane.test.tsx, plugins/specclaw-dash/tests/view.spec.ts, plugins/specclaw-dash/tests/run-mod-tests.sh, plugins/specclaw-dash/README.md, plugins/specclaw-dash/.claude-plugin/plugin.json, plugins/specclaw-dash/.codex-plugin/plugin.json
  - Estimate: large
  - Kind: impl
  - Depends: T1, T2

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
