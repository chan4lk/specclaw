# Tasks: Core — context gate with hand-off, task sizing by context, model by agent type

**Change:** 065-core-context-gate-task-sizing
**Created:** 2026-11-14
**Total Tasks:** 4

## Summary

One Python module and two entry points, then wiring into config, skills and agents, then tests.

## Tasks

### Wave 1 — the module, the CLI and the hook

- [x] `T1` — lib/budget.py, specclaw-budget and the context-gate hook (AC-1..AC-8)
  - Files: plugins/specclaw/lib/budget.py, plugins/specclaw/bin/specclaw-budget, plugins/specclaw/hooks/context-gate, plugins/specclaw/hooks/mod.json, plugins/specclaw/bin/specclaw-timer
  - Kind: impl
  - Context: 60000

### Wave 2 — wiring

- [x] `T2` — builder agents, config template, tasks template, plan and build references (AC-9)
  - Files: plugins/specclaw/agents/builder-backend.md, plugins/specclaw/agents/builder-frontend.md, plugins/specclaw/templates/config.yaml, plugins/specclaw/templates/tasks.md, plugins/specclaw/references/full/plan.md, plugins/specclaw/references/full/build.md
  - Kind: docs
  - Context: 55000
  - Depends: T1

- [x] `T3` — run-context-gate-tests.sh and CI registration (AC-1..AC-9)
  - Files: plugins/specclaw/tests/run-context-gate-tests.sh, .github/workflows/ci.yml
  - Kind: test
  - Context: 50000
  - Depends: T1

### Wave 3 — docs

- [ ] `T4` — CLAUDE.md gate section and tests row, MOD.md hook note
  - Files: plugins/specclaw/CLAUDE.md, plugins/specclaw/MOD.md
  - Kind: docs
  - Context: 40000
  - Depends: T1, T2

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
