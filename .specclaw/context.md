# Project Context

_Last updated: 2026-09-20 — codex-skill-packaging_

## Architecture Overview

<!-- High-level system description: key components, entry points, data flow. -->

specclaw is a Claude Code plugin that drives a spec-first change lifecycle:
`propose` → `plan` → `build` → `verify` → `pr` → _(context auto-updated)_.

- `plugins/specclaw/bin/` — all executable scripts (bash). The mechanical rules of the
  lifecycle live here, one rule per script, so skills call them rather than reimplementing them.
- `plugins/specclaw/skills/` — one `SKILL.md` per lifecycle phase. Markdown wiring only; it
  invokes `bin/` helpers instead of restating their logic.
- `.agents/skills/specclaw/SKILL.md` — the repository-local Codex adapter. It resolves the
  checkout root at runtime and delegates every lifecycle verb to the canonical
  `plugins/specclaw/` skills and executables; it owns no lifecycle implementation or state.
- `plugins/specclaw/templates/` — seed files copied into a new project's `.specclaw/`
  (including `context.md`).
- `plugins/specclaw/tests/` — bash test suites, each registered in `.github/workflows/ci.yml`.
- `.specclaw/` (per project) — durable on-disk record: `config.yaml`, `context.md`,
  `STATUS.md`, and `changes/<NNN>-<slug>/` holding that change's `proposal.md`, `spec.md`,
  `design.md`, `tasks.md`, `verify-report.md`, `review-report.md`, `status.md`, `state.json`,
  and (only while a dispatch is active) `.lock/meta.json`. Completed changes move to
  `changes/archive/<NNN>-<slug>/`. `.specclaw/party/session-spawns.jsonl` is a separate,
  top-level, cross-change ledger — not per-change state.

Change folders carry a permanent three-digit ordinal (`001-init-repo`) assigned once at propose
time by `specclaw-next-change-number` and preserved through archival, so `ls`,
tab-completion, `STATUS.md`, and the GitHub file browser all read chronologically.
`specclaw-update-status` and `specclaw-reconcile` iterate change folders in numeric order,
with unnumbered legacy folders grouped after the numbered ones.

**Per-change dispatch lock.** Every phase dispatch (`plan`, `build`, `verify`, `pr`) acquires
`changes/<change>/.lock/meta.json` via `specclaw-change-lock` before doing any real work, and
releases it on completion — preventing two separately-dispatched forks (a `plan` fork and a
`build` dispatch, a `verify` fork and a `pr` fork) from racing against the same change's files.
Staleness is judged by wall-clock age only (`git.lock_stale_minutes`, default 120), never by PID
liveness — a lock spans a whole skill dispatch across multiple, separately-invoked `bin/`
processes, so there is no single PID whose liveness would mean anything by the time anyone
re-checks it. This is orthogonal to `git.strategy`.

## Coding Style & Conventions

<!-- Language version, formatting rules, naming conventions, comment policy. -->

- **Scripts are bash + coreutils.** `jq` and `python3` may be used in `bin/`; test suites stay
  jq-free (`run-parser-tests.sh` is the one exception and shells out to it).
- **Every test suite must be registered in `.github/workflows/ci.yml`.** An unregistered suite
  silently never runs — this has happened twice in this repo.
- **Codex adapter validation is a focused CI gate.**
  `tests/run-codex-skill-tests.sh` verifies CI registration, runtime root and plugin-root
  resolution, dynamic verb routing, and the adapter's one-file boundary.
- **`tests/shellcheck-gate.sh` must pass with `shellcheck-baseline.txt` unmodified.** Fix a new
  finding or add a targeted `# shellcheck disable=SCxxxx` with a written rationale.
- **Force base ten on any digit run read from disk**: `$((10#$n))`. `$((08))` is a bash syntax
  error, not zero, and a folder named `008-foo` will abort a script that forgets this.
- **Quote every path; never interpolate a change name into a regex.** Change names are opaque
  strings and are tested against shell/regex metacharacters.
- **Version bump before every PR**: `plugins/specclaw/.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` must stay in sync (`specclaw-pr` auto-bumps the patch when
  `plugin.version_files` is configured and the version is unchanged vs. the base branch).
- **JSON written by hand in bash is escaped, even for "trusted" values.** `specclaw-party`'s
  `json_str` and `specclaw-change-lock`'s `json_esc` both escape backslashes/quotes before
  interpolating a shell variable into a JSON literal — cheap, and it stops an unusual `hostname`
  or a future caller's input from producing malformed JSON silently.
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
- **A dispatch lock is anchored at the point with no other legitimate read-only caller — never
  just "a script that already exists for the phase."** `specclaw-verify`'s lock acquire was
  originally placed inside `cmd_collect`, following the instinct "put it in the script whenever
  there's a script to put it in." But `collect` is also invoked standalone as a read-only
  evidence dump, and turning it into a lock-acquiring call made a read-only inspection claim
  exclusive access, orphaning a lock in a real change directory the first time an existing test
  exercised that path. The fix: acquire lives in the `SKILL.md`'s own dispatch-boundary step
  instead (mirroring how `plan`, which has no dedicated binary, already does it); only the
  idempotent `release` stays inside the script. Before anchoring a lock or other mutation to a
  `bin/` subcommand, grep `tests/*.sh` for standalone invocations of that subcommand against real
  data — if any exist, anchor at the `SKILL.md` dispatch boundary instead.
- **Append-only, sum-on-read ledgers for cross-run counts.** `specclaw-timer`'s per-change
  `timeline.jsonl` and `specclaw-party`'s cross-change `party/session-spawns.jsonl` both use the
  same shape: one JSON line per event, no rewrite, total computed by summing matching lines on
  read. Concurrent writers cannot lose each other's lines, and there is nothing to compact.
- **A shared counter's output format is a contract every caller must be updated in lockstep.**
  `specclaw-parse-tasks --count` grew a 4th field (deferred count); every one of its five existing
  callers had to add a 4th `read` variable and update its `'0 0 0'` fallback to `'0 0 0 0'` in the
  same change, because `read`'s overflow behavior (extra fields get appended, with their
  separating whitespace, to the last named variable) would otherwise have silently corrupted the
  `failed` count everywhere it wasn't.
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
- **The concurrency lock uses wall-clock staleness, never PID liveness**, unlike
  `specclaw-browser-lock`'s slot semaphore — see Key Patterns above for why the two mechanisms
  need different liveness signals despite both using the same atomic-`mkdir` claim.

## Constraints

<!-- What NOT to do — banned patterns, deprecated APIs, performance floors, security rules. -->

- **Never write `state.json` directly** — no `sed`, no in-place edit, no new writer. Go through
  `specclaw-set-phase`. When refreshing a record, pass back *every* field it carries
  (`verdict`, `url`, `tasks`, `branch` — or rely on `set-phase`'s documented fallback read):
  `set-phase` rebuilds the record from its arguments, so an omitted field is a deleted field.
- **Never introduce a counter, index, or cache for something the filesystem already states.**
  (An append-only cross-run *ledger*, per Key Patterns above, is a different thing: it records
  events that have no other home, not a derivable fact.)
- **Never silence a shellcheck finding by appending to `shellcheck-baseline.txt`.**
- **Never add a test suite without registering it in `.github/workflows/ci.yml`.**
- **Never copy canonical SpecClaw skills, scripts, templates, or references into the Codex
  adapter.** `.agents/skills/specclaw/` contains only `SKILL.md`; the adapter delegates to
  `plugins/specclaw/` so Claude and Codex share one lifecycle implementation.
- **Never rename or migrate a user's change folders automatically.** Backfills require an
  explicit `--apply` and an explicit yes.
- **Never rename a change while it is mid-build** (live git worktree or checked-out branch) —
  in-flight work still references the old path; refuse instead.
- **Never assume a change folder name starts with a letter, or has a number at all.**
- **Do not sort change folders lexically** where chronological order is the point, and do not
  interleave unnumbered folders at position zero — they belong after the numbered ones.
- **A `--force` flag on a safety check may only override the specific failure mode it documents,
  never the check itself.** `specclaw-change-lock acquire --force` clears a *stale* lock; it
  still refuses a *live* one. A `--force` that always wins just moves the false "I have exclusive
  access" belief one step later.

## Recent Decisions

<!-- Last 5 significant decisions from merged changes. Updated automatically on each PR merge. -->

1. **2026-09-20 — change-concurrency-lock-and-review-budget:** a per-change dispatch lock
   (`specclaw-change-lock`) now guards `plan`/`build`/`verify`/`pr` against concurrent dispatch,
   anchored at each phase's real dispatch boundary (never at a `bin/` subcommand also used
   read-only) and judged stale by wall-clock age alone.
2. **2026-09-20 — codex-skill-packaging:** Codex discovers a repository-local adapter at
   `.agents/skills/specclaw/SKILL.md`; it derives the checkout root at runtime and delegates
   lifecycle routing and bare commands to the canonical `plugins/specclaw/` implementation,
   leaving the Claude skill package untouched.
3. **2026-09-20 — codex-skill-packaging:** the adapter remains exactly one file rather than a
   forked asset tree. Its CI validation pins registration, root resolution, dynamic routing, and
   the no-duplication boundary so the two agent surfaces cannot drift independently.
4. **2026-09-20 — change-concurrency-lock-and-review-budget:** `specclaw-parse-tasks` gained a
   fifth task marker, `[>]` deferred, excluded from `specclaw-validate-change`'s incomplete-task
   gate; its shared `--count` counter grew a 4th field, requiring every existing caller to be
   updated in the same change to avoid `read` silently corrupting the `failed` count.
5. **2026-09-20 — change-concurrency-lock-and-review-budget:** `party.session_spawn_cap` bounds
   cumulative daily party-panel spawns across all changes via a new top-level, append-only
   `party/session-spawns.jsonl` ledger; once set, it forces the "confirm before spending" ask
   even under `party.default: true`.
