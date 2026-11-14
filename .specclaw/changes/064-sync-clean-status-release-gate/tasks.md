# Tasks: Clean-loop PR status, fast track, release gate by severity, CI template

**Change:** 064-sync-clean-status-release-gate
**Created:** 2026-11-14
**Total Tasks:** 5

## Summary

Review core first (gate, class, fast track, debt), then the two PR posters and the release command, then CI
templates and docs. Every task is test first.

## Tasks

### Wave 1 — review core

- [ ] `T1` — `verdict --head`, finding class, `release_gate.block_on`, `review.fast_track`, debt writer (AC-1, AC-4, AC-5)
  - Files: plugins/specclaw-review/lib/review_core.py, plugins/specclaw-review/bin/specclaw-review, plugins/specclaw-review/tests/run-review-tests.sh
  - Kind: impl

### Wave 2 — consumers

- [ ] `T2` — `specclaw-pr` posts the GitHub status through the gate; stubbed-gh tests (AC-2)
  - Files: plugins/specclaw/bin/specclaw-pr, plugins/specclaw/tests/run-review-status-tests.sh
  - Depends: T1
  - Kind: impl
- [ ] `T3` — `specclaw-azdo-pr` posts the AzDO PR status through the gate; stubbed-curl tests (AC-3)
  - Files: plugins/specclaw-sync/bin/specclaw-azdo-pr, plugins/specclaw-sync/tests/run-azdo-review-status-tests.sh
  - Depends: T1
  - Kind: impl
- [ ] `T4` — `specclaw-sync release <base> <target>`; tests (AC-6)
  - Files: plugins/specclaw-sync/bin/specclaw-sync, plugins/specclaw-sync/tests/run-release-tests.sh
  - Depends: T1
  - Kind: impl

### Wave 3 — CI and docs

- [ ] `T5` — CI templates (verdict + gated status), review skill docs, ci.yml suites (AC-7, AC-8)
  - Files: plugins/specclaw-review/ci/github-actions.yml, plugins/specclaw-review/ci/azure-pipelines.yml, plugins/specclaw-review/skills/review/SKILL.md, plugins/specclaw-review/tests/run-review-tests.sh, .github/workflows/ci.yml
  - Depends: T2, T3, T4
  - Kind: config
