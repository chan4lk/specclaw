# Tasks: Show ✅ Approved in proposal.md when a proposal is approved

**Change:** 068-proposal-approved-header
**Created:** 2026-11-16
**Total Tasks:** 3

## Summary

One script change with its tests, one docs wording fix, and the version bump. The code and its tests are one task
on purpose: the tests assert the exact bytes the block writes, and splitting them would only add a hand-off.

## Tasks

### Wave 1 — the fix and its proof

- [x] `T1` — Flip the proposal header in specclaw-set-phase and prove it (AC1–AC6, AC9)
  - Files: plugins/specclaw/bin/specclaw-set-phase, plugins/specclaw/tests/run-phase-state-tests.sh
  - Estimate: small
  - Kind: backend
  - Context: 59700
  - Notes: Block goes right after `mv "$tmpfile" "$STATE_FILE"` / `trap - EXIT`, before the status.md section.
    Tests go before the `Hermeticity` check at the end of the suite: AC1 (Draft → Approved, other lines
    unchanged), AC2 (second `**Status:**` in the body untouched), AC3 (re-run byte-identical, `assert_same_file`),
    AC4 (`✅ Approved 2026-11-14` untouched), AC5 (CRLF fixture keeps `\r`), AC6 (phase spec, status pending, no
    proposal.md, no header line: unchanged, exit 0, state.json still written). Then run
    `run-phase-state-tests.sh`, `run-change-size-tests.sh` and `run-done-guard-tests.sh`.

### Wave 2 — docs and release

- [x] `T2` — Say it in the full propose reference (AC7)
  - Files: plugins/specclaw/references/full/propose.md
  - Estimate: small
  - Kind: docs
  - Context: 33300
  - Depends: T1
  - Notes: Step 10 only. Add that `specclaw-set-phase` also flips the proposal's `**Status:**` header, and
    `then run specclaw-update-status .specclaw`. Do not touch step 6.

- [x] `T3` — Bump the plugin version (AC10)
  - Files: .claude-plugin/marketplace.json, plugins/specclaw/.claude-plugin/plugin.json, plugins/specclaw/.codex-plugin/plugin.json, plugins/specclaw-bf/.claude-plugin/plugin.json, plugins/specclaw-bf/.codex-plugin/plugin.json, plugins/specclaw-dash/.claude-plugin/plugin.json, plugins/specclaw-dash/.codex-plugin/plugin.json, plugins/specclaw-extras/.claude-plugin/plugin.json, plugins/specclaw-extras/.codex-plugin/plugin.json, plugins/specclaw-fleet/.claude-plugin/plugin.json, plugins/specclaw-fleet/.codex-plugin/plugin.json, plugins/specclaw-review/.claude-plugin/plugin.json, plugins/specclaw-review/.codex-plugin/plugin.json, plugins/specclaw-sync/.claude-plugin/plugin.json, plugins/specclaw-sync/.codex-plugin/plugin.json
  - Estimate: small
  - Kind: config
  - Context: 29000
  - Depends: T1, T2
  - Notes: Read the current version on this branch first (0.9.16 at propose time). Patch-increment every
    `plugins/*/.claude-plugin/plugin.json` and every `plugins` entry in `.claude-plugin/marketplace.json` to the
    same value (review rule R1). Own commit: `chore: bump version to X.Y.Z`. Stage by path; the working tree has
    unrelated uncommitted `.specclaw` files that must not be committed.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred — correctly blocked on a sibling change, not incomplete through any fault of its own; excluded from the incomplete-task count that gates `verify`
