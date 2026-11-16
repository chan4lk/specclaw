# Spec: Show ✅ Approved in proposal.md when a proposal is approved

**Change:** 068-proposal-approved-header
**Created:** 2026-11-16
**Status:** 🟡 Draft

## Overview

`specclaw-set-phase <change> proposal approved` records approval in `state.json` and the `Proposal` row of
`status.md`, but leaves the `**Status:** 🟡 Draft` line at the top of `proposal.md` as it was. This change makes
`specclaw-set-phase` flip that line to `✅ Approved` on approval, so the file people open agrees with the records.
It also closes a docs gap in the full-flow propose reference, which never refreshes the dashboard after approval.
Future approvals only: no existing `proposal.md` is rewritten.

## Requirements

### Functional Requirements

- **FR1.** On `specclaw-set-phase … proposal approved` (status compared case-insensitively), the first line of
  `<change>/proposal.md` that starts with `**Status:**` becomes exactly `**Status:** ✅ Approved`.
- **FR2.** Only that first `**Status:**` line is considered. Later `**Status:**` lines in the body are untouched.
- **FR3.** If that first line already contains the word `Approved`, the file is left byte-identical (hand-written
  forms such as `✅ Approved 2026-11-14` or `🟢 Approved (operator, …)` are never overwritten).
- **FR4.** The new text carries no date, so running the same approval again leaves the file byte-identical.
- **FR5.** A trailing carriage return on the old line is kept, so a CRLF file does not gain an LF-only line.
- **FR6.** The change is skipped, with no error and no warning, when the phase is not `proposal`, the status is not
  `approved`, `proposal.md` does not exist, or it has no `**Status:**` line. The phase transition itself
  (`state.json`, `status.md`) is recorded exactly as before in every one of those cases.
- **FR7.** `references/full/propose.md` step 10 says that `specclaw-set-phase` also flips the proposal's
  `**Status:**` header, and tells the operator-facing flow to run `specclaw-update-status .specclaw` after it.

### Non-Functional Requirements

- **NFR1.** A failure to rewrite the header must never fail or roll back the phase transition: at worst it warns on
  stderr and the command still exits 0 (the same rule the `status.md` row write follows).
- **NFR2.** The rewrite is atomic enough not to leave a truncated file: written to a temp file, checked non-empty,
  then copied over (the pattern `specclaw-status-row` uses).
- **NFR3.** No new dependency: bash and awk only, as in the rest of the script.
- **NFR4.** No existing `proposal.md` in `.specclaw/changes/` or `.specclaw/changes/archive/` is modified.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1.** Given a `proposal.md` whose line 4 is `**Status:** 🟡 Draft`, running
  `specclaw-set-phase <spec> <change> proposal approved` makes line 4 exactly `**Status:** ✅ Approved` and changes
  no other line.
- **AC2.** Given a proposal with a second `**Status:** …` line in its body, only the first is changed.
- **AC3.** Running the same approval a second time leaves `proposal.md` byte-identical.
- **AC4.** Given line 4 already `**Status:** ✅ Approved 2026-11-14`, the file is byte-identical after approval.
- **AC5.** Given a CRLF `proposal.md`, line 4 after approval is `**Status:** ✅ Approved` followed by `\r\n`, and
  every other line still ends in `\r\n`.
- **AC6.** For each of: phase `spec`, status `pending`, no `proposal.md`, a `proposal.md` with no `**Status:**` line
  — `proposal.md` is unchanged (or absent), the command exits 0, and the transition is recorded in `state.json`.
- **AC7.** `references/full/propose.md` step 10 contains both the `specclaw-update-status` call and the mention
  that `set-phase` flips the `**Status:**` header.
- **AC8.** `git diff --name-only` for the change lists no file under `.specclaw/changes/` other than this change's
  own folder.
- **AC9.** `run-phase-state-tests.sh`, `run-change-size-tests.sh` and `run-done-guard-tests.sh` all pass.
- **AC10.** Every `plugins/*/.claude-plugin/plugin.json` and every entry in `.claude-plugin/marketplace.json` carry
  the same new patch version, in a commit of their own.

## Edge Cases

- A proposal whose first `**Status:**` line has a custom value such as `🟡 Proposed`: treated as not-approved and
  rewritten to `✅ Approved`.
- `proposal.md` with no trailing newline, or empty: handled by awk without adding or dropping anything but the
  one line; an empty file has no header, so it is skipped (FR6).
- A change name with characters special to sed or awk: the path is passed as an argument, never interpolated into
  a pattern.
- `--force` re-approval after a later phase: still `proposal approved`, still idempotent (FR3, FR4).
- Lean flow changes (`change.md`, no `proposal.md`): FR6 skip; nothing is created.
- `specclaw-set-size` re-records `proposal approved --size …`: same path, same idempotent result.

## Dependencies

- `plugins/specclaw/bin/specclaw-set-phase` is the only phase writer; nothing else may be taught to edit the header.
- Suites that call `proposal approved` and must stay green: `run-change-size-tests.sh`, `run-done-guard-tests.sh`.

## Approach

- Add one block to `bin/specclaw-set-phase`, straight after `state.json` is installed (`mv … "$STATE_FILE"`,
  before the status.md section), so a status.md edge case that exits early can never skip it.
- Guard: `PHASE = proposal`, lowercased `STATUS = approved`, `"$CHANGE_DIR/proposal.md"` is a file.
- awk to a temp file: change only the first `^\*\*Status:\*\*` line, skip it if it already contains `Approved`,
  keep a trailing `\r`; then `cat tmp > proposal.md` if the temp file is non-empty. Any failure is a `warn`.
- File map: `plugins/specclaw/bin/specclaw-set-phase` (the block), `plugins/specclaw/references/full/propose.md`
  (step 10 wording), `plugins/specclaw/tests/run-phase-state-tests.sh` (new cases before the Hermeticity check),
  version files (separate `chore: bump version` commit).
- Decision: no date in the header, because the date is already in `state.json` and a date would break byte-identity
  across days.

## Notes

- The new `proposal.md` for this change itself still says `🟡 Draft`: it was approved before the fix existed, and
  existing proposals are deliberately not edited (NFR4).
- Out of scope, noted for later: `templates/spec.md` has the same `🟡 Draft` header after `plan`.
