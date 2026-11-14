# Tasks: specclaw-review — a local review loop that converges

**Change:** 044-fast-review-loop
**Created:** 2026-10-16
**Total Tasks:** 11

## Summary

Wave 1 builds the plugin core (library + CLI + rule packs). Wave 2 adds the MCP server, guard hook, skills and CI snippets on top of it. Wave 3 wires core and packaging, adds the offline suite, and smoke-tests on Project A.

## Tasks

### Wave 1 — Plugin core

- [x] `T1` — Core library + CLI: config, rules, classify, diff/impact, prompt, backend, parse, calibrate, rounds, verdict, learn, stats, lazy init (AC-1–AC-9, AC-13–AC-15)
  - Files: plugins/specclaw-review/bin/specclaw-review, plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/lib/review_memory.py
  - Estimate: large
  - Kind: impl

- [x] `T2` — Rule packs base/python/node/react-spa/nextjs/dotnet with stable IDs; base carries Project A's distilled lessons (AC-1)
  - Files: plugins/specclaw-review/review-rules/base.md, plugins/specclaw-review/review-rules/python.md, plugins/specclaw-review/review-rules/node.md, plugins/specclaw-review/review-rules/react-spa.md, plugins/specclaw-review/review-rules/nextjs.md, plugins/specclaw-review/review-rules/dotnet.md
  - Estimate: medium
  - Kind: docs

### Wave 2 — Interfaces

- [x] `T3` — MCP server + .mcp.json; guard hook + hooks.json; claude rules template (AC-10–AC-12)
  - Files: plugins/specclaw-review/mcp/server.py, plugins/specclaw-review/.mcp.json, plugins/specclaw-review/hooks/hooks.json, plugins/specclaw-review/hooks/guard-memory, plugins/specclaw-review/templates/claude-rule.md
  - Depends: T1
  - Estimate: medium
  - Kind: impl

- [x] `T4` — Skills (review loop, learn) and CI snippets
  - Files: plugins/specclaw-review/skills/review/SKILL.md, plugins/specclaw-review/skills/learn/SKILL.md, plugins/specclaw-review/ci/azure-pipelines.yml, plugins/specclaw-review/ci/github-actions.yml
  - Depends: T1
  - Estimate: small
  - Kind: docs

### Wave 3 — Wiring, tests, smoke

- [x] `T5` — Core hooks (lean+full verify/pr docs, specclaw-pr + specclaw-azdo-pr review line), manifests, marketplaces, version 0.8.2, context.md (AC-16, AC-17)
  - Files: plugins/specclaw/bin/specclaw-pr, plugins/specclaw-sync/bin/specclaw-azdo-pr, plugins/specclaw/skills/verify/SKILL.md, plugins/specclaw/skills/pr/SKILL.md, plugins/specclaw/references/full/verify.md, plugins/specclaw/references/full/pr.md, plugins/specclaw-review/.claude-plugin/plugin.json, plugins/specclaw-review/.codex-plugin/plugin.json, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json, plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .specclaw/context.md
  - Depends: T1
  - Estimate: medium
  - Kind: config

- [x] `T6` — Offline regression suite with stub backend, registered in CI (AC-1–AC-17)
  - Files: plugins/specclaw-review/tests/run-review-tests.sh, .github/workflows/ci.yml, tests/run-codex-plugin-tests.sh
  - Depends: T1, T3, T5
  - Estimate: large
  - Kind: test

- [x] `T7` — Smoke run on a Project A change with the real backend, locally, no push (AC-18)
  - Files: .specclaw/changes/044-fast-review-loop/smoke-replay.md
  - Depends: T6
  - Estimate: small
  - Kind: test

### Wave 4 — Parity with the PR review (operator, 2026-10-16)

- [x] `T8` — Passes, reviewer tools, live governance, docs visible in the diff (FR-18–FR-21, AC-19–AC-22)
  - Files: plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/skills/review/SKILL.md
  - Estimate: medium
  - Kind: impl

- [x] `T9` — Tests for AC-19–AC-22
  - Files: plugins/specclaw-review/tests/run-review-tests.sh
  - Depends: T8
  - Estimate: small
  - Kind: test

- [x] `T10` — Project A parity replay (match-Project-A mode) + cheaper modes, written up (AC-23)
  - Files: .specclaw/changes/044-fast-review-loop/smoke-replay.md
  - Depends: T8
  - Estimate: small
  - Kind: test

- [x] `T11` — `specclaw-review discover` + `rules` skill: find the repo's governance, suggest config, draft rule files from its own review history (FR-22, AC-25, AC-26)
  - Files: plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/bin/specclaw-review, plugins/specclaw-review/mcp/server.py, plugins/specclaw-review/skills/rules/SKILL.md, plugins/specclaw-review/tests/run-review-tests.sh
  - Estimate: medium
  - Kind: impl
