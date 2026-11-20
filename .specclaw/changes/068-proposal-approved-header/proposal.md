# Proposal: Show ✅ Approved in proposal.md when a proposal is approved

**Created:** 2026-11-16
**Status:** 🟡 Draft

## Problem

When a proposal is approved, `specclaw-set-phase <change> proposal approved` records it in `state.json` and in the
`Proposal` row of `status.md`. It never touches the `**Status:** 🟡 Draft` line at the top of `proposal.md`, so an
approved, even fully built, change still reads "Draft" in the file people open first.

Seen in the repo: 43 of 68 archived proposals say Draft or Proposed, and 23 of those have `✅ Approved` in their
`status.md`. The few `✅ Approved <date>` headers (059 to 065) were typed by hand after approval; no script writes
them. A clean full-flow run in a sandbox (change `068-add-version-flag`, current sources) confirmed it: the header
stayed `🟡 Draft` across the approval commit, and only `state.json` and the `status.md` row changed.

Related gap from the same run: the full-flow `references/full/propose.md` runs `specclaw-update-status` at step 6,
before approval, and step 10 (approval) never re-runs it, so the dashboard `STATUS.md` also keeps saying Draft.
The lean `skills/propose/SKILL.md` already re-runs it after approval.

## Proposed Solution

Make the one script that owns approval also update the header.

- In `plugins/specclaw/bin/specclaw-set-phase`, after the `Proposal` row is written, when the phase is `proposal` and
  the status is `approved`, rewrite the first `**Status:**` line of the change's `proposal.md` to
  `**Status:** ✅ Approved`.
  - It leaves a header that already says `Approved` alone, so hand-written forms such as
    `✅ Approved (operator, …)` are never overwritten.
  - It writes no date, so re-running with the same input leaves the file byte-identical. The approval time is
    already in `state.json`.
  - It keeps a trailing carriage return if the file uses CRLF line endings.
  - A missing `proposal.md` or a missing header is skipped silently. It never fails the transition.
- In `references/full/propose.md` step 10, add "then run `specclaw-update-status .specclaw`" and say that
  `specclaw-set-phase` also flips the proposal's `**Status:**` header.
- Add tests to `plugins/specclaw/tests/run-phase-state-tests.sh`.

## Scope

### In Scope
- `specclaw-set-phase` header update on `proposal approved`.
- The one-line docs fix in `references/full/propose.md` step 10.
- Tests for the header update.
- A version bump commit (repo rule), on branch `specclaw/chore`.

### Out of Scope
- **Existing proposals.** No `proposal.md` already in `changes/` or `changes/archive/` is edited. Future approvals only.
- The `🟡 Draft` header in `templates/spec.md`, which has the same problem after `plan`. Separate change.
- Updating the header on later phases (build, verify, pr, archive). It flips once, at approval.
- The lean flow, which has no `proposal.md` header (its page is `change.md`).
- No push and no pull request from this change; the operator opens the PR from `specclaw/chore` later.

## Impact

- **Size:** bounded (alters an existing flow, `specclaw-set-phase`, in one script plus one doc line and its tests)
- **Files affected:** 3 plus version files (`bin/specclaw-set-phase`, `references/full/propose.md`,
  `tests/run-phase-state-tests.sh`)
- **Complexity:** small
- **Risk:** low. `set-phase` is the only phase writer and many suites call `proposal approved`; the new block is
  skipped on any missing file, so it cannot fail a transition.

## Open Questions

- The next number on this branch is 068, but the `specclaw/security` branch already has a
  `068-preset-security-rules` (and a 069). The repo already tolerates duplicate numbers (046 and 066 appear twice),
  and the folder names differ, so there is no file collision. Say if you want a different number instead.

---

**To proceed:** Review this proposal and approve to begin planning.
