# Spec: Numbered change folders

**Change:** numbered-change-folders
**Created:** 2026-08-08
**Status:** 🟡 Draft

## Overview

Every change folder gets a permanent three-digit ordinal prefix — `.specclaw/changes/001-init-repo/` — assigned once at propose time and carried through archival. Existing repos are never rewritten automatically: specclaw surfaces that unnumbered folders exist and offers a dry-run backfill the user must explicitly accept.

Three digits, not two. Thirty numbers are already spoken for in this repo alone, produced in roughly four months. Two digits would exhaust inside a year and fail silently rather than loudly, because `100-foo` sorts *before* `99-foo` lexically — breaking the very `ls` ordering this change exists to provide.

## Requirements

### Functional Requirements

**Number derivation**

- **FR1** — `specclaw-next-change-number <specclaw_dir>` prints the next available change number, zero-padded to three digits, and exits 0.
- **FR2** — It derives the number by scanning both `changes/*/` and `changes/archive/*/`, taking the maximum leading integer found and adding one. The number is derived from disk on every call; no counter file is created or read.
- **FR3** — With no numbered folders anywhere (including a completely empty `changes/`), it prints `001`.
- **FR4** — Gaps are preserved. If `001` and `007` exist, the next number is `008`, not `002`. A deleted change retires its number.
- **FR5** — Folder names that do not begin with digits are ignored when taking the maximum, as is the literal `archive` directory. Numbered and unnumbered folders coexisting is a supported state, not an error.
- **FR5a** — A folder counts as **numbered** only if its name matches `^[0-9]+-` **and does not** match `^[0-9]{4}-[0-9]{2}-[0-9]{2}`. The second clause excludes the legacy `YYYY-MM-DD-` archive prefix, whose leading run of digits is a *year*, not an ordinal. Without it, `2026-07-22-build-engine` reads as change number 2026 and the next proposal on this repo becomes `2027-<slug>` — permanently poisoning the sequence. The exclusion is deliberately narrow: it fires only on the full date shape, so a genuine ordinal such as `2026-some-slug` still counts as numbered. This definition is the single rule; every consumer applies it identically.

**Assignment and archival**

- **FR6** — `/specclaw:propose` creates `.specclaw/changes/<NNN>-<slug>/`, where `<NNN>` comes from `specclaw-next-change-number` and `<slug>` is the existing slugification of the user's idea.
- **FR7** — `/specclaw:archive` moves a change to `.specclaw/changes/archive/<name>/` preserving its name verbatim, including its number. The `YYYY-MM-DD-` archive-date prefix is removed from the naming rule; the archive date remains recorded in `state.json`.

**Backfill**

- **FR8** — `specclaw-renumber-changes <specclaw_dir> [--apply] [--force]` assigns numbers to existing unnumbered folders across both `changes/` and `changes/archive/`.
- **FR9** — It is dry-run by default. Without `--apply` it prints every planned rename as `old → new` and makes no filesystem modification whatsoever.
- **FR10** — Ordering is by creation date ascending, resolved per folder in this precedence: the `**Created:**` line in `proposal.md`; else the folder's first-commit date from git; else a leading `YYYY-MM-DD-` archive prefix on the folder name; else the folder sorts last. Ties break by folder name so the ordering is deterministic.
- **FR11** — It refuses to run, with a non-zero exit and an explanatory message, when any change folder is already numbered. `--force` overrides, renumbering every folder from `001` in date order.
- **FR12** — It refuses to run while any change is mid-build — a live git worktree or a checked-out branch for that change — because those still reference the old path.
- **FR13** — It aborts before performing any rename if a planned target path already exists.
- **FR14** — Renames use `git mv` inside a git working tree and plain `mv` otherwise.
- **FR15** — After renaming a folder that has a `state.json`, the recorded `change` field is refreshed by re-invoking `specclaw-set-phase` at the change's current phase and status. `specclaw-set-phase` remains the only writer of phase state; this script never edits `state.json` directly.

**Discovery and ordering**

- **FR16** — `specclaw-update-status` and `specclaw-reconcile` iterate change folders in numeric order, with unnumbered folders grouped after all numbered ones, so `STATUS.md` reads chronologically.
- **FR17** — `/specclaw:status` prints one hint line when unnumbered folders exist, naming the count and `/specclaw:renumber`. It is a hint, not a prompt, and it is absent when the count is zero.
- **FR18** — `/specclaw:propose`, when it detects unnumbered folders, shows the dry-run plan and asks once whether to apply it. Declining proceeds with creating the new numbered change alone.
- **FR19** — A new `/specclaw:renumber` skill wraps `specclaw-renumber-changes` so the backfill has a name a user can be pointed at.

Neither FR17 nor FR18 needs an "already asked" flag: both are conditioned on unnumbered folders existing, so they self-clear the moment a backfill runs.

### Non-Functional Requirements

- **NFR1** — New scripts are bash plus coreutils, consistent with `bin/`. `jq` and `python3` may be used in `bin/` as existing scripts do; the test suite itself stays jq-free.
- **NFR2** — Both new scripts pass `tests/shellcheck-gate.sh` with no additions to `shellcheck-baseline.txt`. A genuine exception takes a targeted `# shellcheck disable=` with a written rationale.
- **NFR3** — The new test suite is registered in `.github/workflows/ci.yml`. An unregistered suite silently never runs, which has already happened twice in this repo.
- **NFR4** — No new keys in `config.yaml`. The numbering format is a single fixed rule.
- **NFR5** — Existing changes keep working untouched until a user opts into the backfill. No lifecycle command may fail because a folder lacks a number.
- **NFR6** — `specclaw-next-change-number` completes without network access and in well under a second for a repo with hundreds of changes.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — In a fixture with an empty `changes/`, `specclaw-next-change-number` prints exactly `001`.
- **AC2** — With `changes/001-a/` and `changes/archive/007-b/`, it prints `008` — proving the archive is scanned and gaps are preserved.
- **AC3** — With only unnumbered folders present, it prints `001` and exits 0.
- **AC4** — With `changes/008-a/` present, it prints `009`. (Guards the leading-zero octal trap: unquoted `$((08))` is a bash syntax error.)
- **AC5** — With `changes/999-a/` present, it prints `1000` — the width widens rather than truncating or wrapping.
- **AC6** — A folder literally named `archive` and a folder named `archive-cleanup` are both handled: neither is treated as a numbered change, and the run exits 0.
- **AC6a** — With `changes/archive/2026-07-22-build-engine/` as the only populated folder, `specclaw-next-change-number` prints `001` — the legacy date prefix is not read as ordinal 2026 (FR5a). Run against this repository's real `.specclaw`, it prints `001` before the backfill and `032` after it, and in neither case `2027`.

  The pre-backfill answer is `001`, not `031`, because FR2 derives the maximum plus one rather than counting folders: 31 unnumbered folders contribute nothing to a maximum. `032` is the post-backfill answer because the backfill numbers 31 folders `001`–`031`, including this change's own. An earlier draft of this criterion asserted `031` and was wrong on both counts — it applied counter semantics that FR2 and FR4 explicitly reject.
- **AC6b** — `changes/2026-some-slug/` *is* treated as numbered, yielding `2027`. The FR5a exclusion fires only on the full `YYYY-MM-DD` shape, never on any leading four-digit run.
- **AC7** — `specclaw-renumber-changes <dir>` without `--apply` produces a full `old → new` plan on stdout and leaves `ls changes/` byte-identical.
- **AC8** — With `--apply` on a fixture of three unnumbered folders whose `proposal.md` `Created:` dates are out of alphabetical order, the resulting names are `001-`, `002-`, `003-` in date order, not name order.
- **AC9** — A folder whose `proposal.md` lacks a `Created:` line is still ordered, via the git-first-commit fallback, and never crashes the run.
- **AC10** — Two folders sharing one `Created:` date produce a stable, name-ordered result across repeated runs.
- **AC11** — Given a fixture where any folder is already numbered, the script exits non-zero with an explanatory message and renames nothing. The same fixture with `--force --apply` renumbers all folders from `001`.
- **AC12** — When a planned target already exists, the script aborts before the first rename; no folder is moved.
- **AC13** — After `--apply` on a folder with a `state.json`, that file's `change` field equals the new folder name, its `phase` and per-phase records are otherwise unchanged, and the file parses as JSON.
- **AC14** — After `--apply`, `specclaw-reconcile` on the fixture reports zero drift.
- **AC15** — `/specclaw:propose` on a fixture with `001-a` and `002-b` creates `003-<slug>/` containing `proposal.md` and `status.md`.
- **AC16** — `/specclaw:archive` on `003-foo` produces `changes/archive/003-foo/` — number preserved, no date prefix.
- **AC17** — `STATUS.md` generated from a fixture containing `010-a`, `002-b`, and `unnumbered-c` lists them in the order `002-b`, `010-a`, `unnumbered-c` — numeric, not lexical, with unnumbered last.
- **AC18** — With unnumbered folders present, `specclaw-update-status` output carries the hint line and its count; with none present, no hint line appears anywhere.
- **AC19** — `bash tests/shellcheck-gate.sh` exits 0 with `shellcheck-baseline.txt` unmodified.
- **AC20** — The new suite name appears in `.github/workflows/ci.yml` and the full suite passes locally.

## Edge Cases

1. **Empty `changes/`** — the glob matches nothing; `[ -d "$d" ] || continue` must handle the literal unexpanded pattern. Result is `001`, not an error.
2. **`archive/` absent** — a fresh project may have no archive directory. Scanning must skip it silently.
3. **Leading-zero octal trap** — `$((08))` is a bash syntax error. All numeric comparison must force base ten with `10#`. This is the single most likely defect in the change.
4. **Overflow past 999** — `printf '%03d' 1000` widens to `1000`. Correct, and lexical ordering only breaks at four digits, which is decades away at any plausible rate. Documented, not defended against.
5. **Folder named `archive`** — reserved; never a change. A folder named `archive-cleanup` is an ordinary unnumbered change and must not be confused for it.
6. **No `proposal.md` at all** — a partially-created folder. Ordering falls through to the git and prefix fallbacks; the run must not abort.
7. **Old archive date prefix** — `2026-07-22-build-engine` yields date `2026-07-22` from the prefix as a last resort, and the prefix is stripped when the new name is formed, giving `014-build-engine` rather than `014-2026-07-22-build-engine`. Critically, such a folder is **unnumbered** per FR5a, so it neither raises the maximum nor trips the FR11 already-numbered refusal. This repository has 26 of them; getting it wrong makes the backfill refuse on the one repo it exists to migrate.
8. **Interrupted `--apply`** — a partial rename leaves a mixed state. Re-running then hits FR11 and refuses; `--force` is the documented recovery. The pre-flight collision check (FR13) keeps the failure mode "stopped early", never "clobbered".
9. **Names with shell or regex metacharacters** — already exercised for `state.json` by `run-phase-state-tests.sh` case E11. All paths stay quoted and no name is interpolated into a regex.
10. **Missing `state.json`** — pre-`set-phase` changes have none. Rename proceeds; the FR15 refresh is skipped, not failed.
11. **Not a git repository** — `git mv` is unavailable; fall back to `mv` (FR14).
12. **A change mid-build** — a live worktree still points at the old path. FR12 refuses rather than corrupting an in-flight build.
13. **Ordering with mixed numbered and unnumbered folders** — FR16 puts unnumbered last rather than interleaving them at position zero.

## Dependencies

- `specclaw-set-phase` — reused for the FR15 `change`-field refresh. Not modified.
- `specclaw-status-row` — reached only indirectly via `set-phase`. Not modified.
- `tests/shellcheck-gate.sh` and `shellcheck-baseline.txt` — gate both new scripts.

Resolved during planning: **nothing reads the `change` field.** It is written by `specclaw-set-phase` and `specclaw-verify` as provenance and read by no script in `bin/`. A rename therefore causes no functional drift — only a stale label, which FR15 corrects. This closes the proposal's first open question and is why the backfill needs no new state-writing code.

## Notes

The proposal's second open question — whether the propose-time offer should fire on repos with large legacy counts — is settled as "always offer". It is one declinable line, and the dry-run makes the scope visible before anything moves.

This change's own folder is deliberately unnumbered. The backfill will assign it a number, which doubles as the first end-to-end exercise of the tool.
