# Tasks: Review — lesson recall at plan/build, fix-proves-test, lesson promotion

**Change:** 061-review-recall-fix-proof
**Created:** 2026-11-14
**Total Tasks:** 3

## Summary

Fix proof and promotion threshold in the core (tests first), then the recall hook, then rules and skill docs.

## Tasks

### Wave 1 — Core

- [ ] `T1` — Fix proof in `run --since` and `--final`, carried findings, `learn_threshold` (AC-3…AC-7)
  - Files: plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/bin/specclaw-review, plugins/specclaw-review/mcp/server.py, plugins/specclaw-review/tests/run-review-tests.sh
  - Estimate: medium
  - Kind: impl

- [ ] `T2` — Recall hook and its registration (AC-1, AC-2)
  - Files: plugins/specclaw-review/hooks/recall, plugins/specclaw-review/hooks/hooks.json, plugins/specclaw-review/lib/review_memory.py, plugins/specclaw-review/tests/run-review-tests.sh
  - Estimate: small
  - Kind: impl

### Wave 2 — Rules and docs

- [ ] `T3` — B11, B12 in `base.md`; review and learn skills describe fix proof, recall and the threshold (AC-8)
  - Files: plugins/specclaw-review/review-rules/base.md, plugins/specclaw-review/skills/review/SKILL.md, plugins/specclaw-review/skills/learn/SKILL.md, plugins/specclaw-review/tests/run-review-tests.sh
  - Estimate: small
  - Kind: docs
  - Depends: T1, T2

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred — correctly blocked on a sibling change, not incomplete through any fault of its own; excluded from the incomplete-task count that gates `verify`
