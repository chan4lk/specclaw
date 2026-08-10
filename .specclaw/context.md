# Project Context

_Last updated: 2026-08-10 — numbered-change-folders_

## Architecture Overview

<!-- High-level system description: key components, entry points, data flow. -->

specclaw is a Claude Code plugin that drives a spec-first change lifecycle:
`propose` → `plan` → `build` → `verify` → `pr` → _(context auto-updated)_.

- `plugins/specclaw/bin/` — all executable scripts (bash). The mechanical rules of the
  lifecycle live here, one rule per script, so skills call them rather than reimplementing them.
- `plugins/specclaw/skills/` — one `SKILL.md` per lifecycle phase. Markdown wiring only; it
  invokes `bin/` helpers instead of restating their logic.
- `plugins/specclaw/templates/` — seed files copied into a new project's `.specclaw/`
  (including `context.md`).
- `plugins/specclaw/tests/` — bash test suites, each registered in `.github/workflows/ci.yml`.
- `.specclaw/` (per project) — durable on-disk record: `config.yaml`, `context.md`,
  `STATUS.md`, and `changes/<NNN>-<slug>/` holding that change's `proposal.md`, `spec.md`,
  `design.md`, `tasks.md`, `verify-report.md`, `review-report.md`, `status.md`, `state.json`.
  Completed changes move to `changes/archive/<NNN>-<slug>/`.

Change folders carry a permanent three-digit ordinal (`001-init-repo`) assigned once at propose
time by `specclaw-next-change-number` and preserved through archival, so `ls`,
tab-completion, `STATUS.md`, and the GitHub file browser all read chronologically.
`specclaw-update-status` and `specclaw-reconcile` iterate change folders in numeric order,
with unnumbered legacy folders grouped after the numbered ones.

## Coding Style & Conventions

<!-- Language version, formatting rules, naming conventions, comment policy. -->

- **Scripts are bash + coreutils.** `jq` and `python3` may be used in `bin/`; test suites stay
  jq-free (`run-parser-tests.sh` is the one exception and shells out to it).
- **Every test suite must be registered in `.github/workflows/ci.yml`.** An unregistered suite
  silently never runs — this has happened twice in this repo.
- **`tests/shellcheck-gate.sh` must pass with `shellcheck-baseline.txt` unmodified.** Fix a new
  finding or add a targeted `# shellcheck disable=SCxxxx` with a written rationale.
- **Force base ten on any digit run read from disk**: `$((10#$n))`. `$((08))` is a bash syntax
  error, not zero, and a folder named `008-foo` will abort a script that forgets this.
- **Quote every path; never interpolate a change name into a regex.** Change names are opaque
  strings and are tested against shell/regex metacharacters.
- **Version bump before every PR**: `plugins/specclaw/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` must stay in sync.
- Where a helper function is deliberately duplicated between two standalone executables (no
  sourcing convention exists between them), the copies are kept byte-identical and a test pins
  that identity.

## Key Patterns

<!-- Reusable patterns used across the codebase — auth, error handling, data access, logging, etc. -->

- **Derived, not stored.** Facts already present on disk are recomputed, never cached in a
  counter or index file. A second copy of a fact is a thing that drifts.
  `specclaw-next-change-number` takes the maximum ordinal on disk plus one on every call.
- **One writer per piece of state.** `specclaw-set-phase` is the only writer of
  `changes/<change>/state.json` — not a script, not a skill, not the model editing `status.md`
  prose. Callers that need to change state re-invoke `set-phase` rather than editing the file
  (writes are atomic: temp file → parse check → `mv`; `at` is preserved when the record is
  otherwise unchanged, so idempotent refreshes do not churn timestamps).
- **Plan → validate → execute for destructive operations.** All refusals happen before the
  first filesystem mutation, so the failure mode is "stopped early", never "clobbered halfway".
- **Destructive tools are dry-run by default.** `specclaw-renumber-changes` prints an
  `old → new` plan and requires `--apply` to move anything. Migrations are offered, never
  imposed: upgrading specclaw renames nothing in a user's repo.
- **Self-clearing hints instead of "already asked" flags.** Prompts and hint lines are
  conditioned on the underlying condition still being true (e.g. unnumbered folders existing),
  so they disappear on their own and need no new state.
- **Fallback chains with a documented precedence order** for facts that may be missing — e.g.
  resolving a change's creation date: `**Created:**` in `proposal.md` → the folder's
  first-commit date from git → a leading `YYYY-MM-DD-` on the folder name → sorts last. Ties
  break by name so repeated runs are deterministic.
- **`git mv` inside a working tree, plain `mv` outside it.**
- **Mixed old/new states are supported steady states, not errors.** No lifecycle command may
  fail because a folder predates a convention.

## Technology Decisions

<!-- Why specific libraries/frameworks were chosen; version pins and why; migration paths. -->

- **Bash + coreutils for all of `bin/`** — the plugin ships as scripts a Claude Code skill can
  invoke directly, with no build step or runtime to install.
- **Three-digit change ordinals** (`NNN-<slug>`), not two. At this repo's rate two digits
  exhaust inside a year, and the overflow fails *silently*: `100-foo` sorts before `99-foo`
  lexically, breaking the exact ordering the numbering exists to provide. `printf '%03d'` is a
  minimum width, so passing 999 widens the name rather than colliding.
- **`^[0-9]+-` and NOT `^[0-9]{4}-[0-9]{2}-[0-9]{2}` is the single definition of "numbered"** —
  the second clause excludes the legacy `YYYY-MM-DD-` archive prefix, whose leading digit run
  is a year. Without it this repo's 26 archived folders put the maximum at 2026 and the next
  proposal becomes `2027-<slug>`, poisoning the sequence permanently. Every consumer applies
  this rule identically.
- **Archive folders keep the number and drop the date prefix.** The old prefix was the
  *archive* date, not the change's — one bulk run stamped 24 folders with the same date, so
  ordering by it was actively misleading. The archive date lives in `state.json`.
- **No new `config.yaml` keys for the numbering format.** It is one fixed rule.

## Constraints

<!-- What NOT to do — banned patterns, deprecated APIs, performance floors, security rules. -->

- **Never write `state.json` directly** — no `sed`, no in-place edit, no new writer. Go through
  `specclaw-set-phase`. When refreshing a record, pass back *every* field it carries
  (`verdict`, `url`, `tasks`, `branch` — or rely on `set-phase`'s documented fallback read):
  `set-phase` rebuilds the record from its arguments, so an omitted field is a deleted field.
- **Never introduce a counter, index, or cache for something the filesystem already states.**
- **Never silence a shellcheck finding by appending to `shellcheck-baseline.txt`.**
- **Never add a test suite without registering it in `.github/workflows/ci.yml`.**
- **Never rename or migrate a user's change folders automatically.** Backfills require an
  explicit `--apply` and an explicit yes.
- **Never rename a change while it is mid-build** (live git worktree or checked-out branch) —
  in-flight work still references the old path; refuse instead.
- **Never assume a change folder name starts with a letter, or has a number at all.**
- **Do not sort change folders lexically** where chronological order is the point, and do not
  interleave unnumbered folders at position zero — they belong after the numbered ones.

## Recent Decisions

<!-- Last 5 significant decisions from merged changes. Updated automatically on each PR merge. -->

1. **2026-08-10 — numbered-change-folders:** change folders carry a permanent three-digit
   ordinal (`NNN-<slug>`) assigned at propose time and kept through archival; the number is
   derived from disk (max + 1) on every call, with no counter file, so gaps are permanent and a
   number always means the same change.
2. **2026-08-10 — numbered-change-folders:** the backfill (`specclaw-renumber-changes`) is
   opt-in — dry-run by default, `--apply` required, `--force` to renumber already-numbered
   folders and to recover from an interrupted run — and mixed numbered/unnumbered repos are a
   supported steady state.
3. **2026-08-10 — numbered-change-folders:** renaming a change refreshes `state.json` by
   re-invoking `specclaw-set-phase` rather than editing the file, keeping the
   one-writer-per-state invariant intact; archived folders are skipped because `set-phase`
   resolves `changes/<change>` and would record a path as the change identity.
