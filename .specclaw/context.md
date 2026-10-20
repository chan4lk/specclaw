# Project Context

_Last updated: 2026-10-20 — 046-macos-test-portability_

## Architecture Overview

specclaw is a marketplace of five Claude Code plugins, each with a native Codex manifest, that
drives the spec-first lifecycle `propose` → `plan` → `build` → `verify` → `pr`:

- `plugins/specclaw/` — core lifecycle. `specclaw-flow` returns `lean` (one `change.md` per change
  plus `.specclaw/mock/index.html`) or `full` (no `flow` key; skills dispatch to
  `references/full/<phase>.md`).
- `plugins/specclaw-bf/`, `plugins/specclaw-sync/`, `plugins/specclaw-extras/` — add-ons
  (brownfield, tracker sync, automation/knowledge/review panel). Core never runs an add-on script
  without a `command -v` guard; add-on scripts call core scripts by bare name, with a PATH fallback
  to `../../specclaw/bin`. All ten manifests and both marketplaces share one version.
- `plugins/specclaw-review/` — the local review loop (change 044). It is python3-stdlib only: one core library
  (`lib/review_core.py`, `lib/review_memory.py`) behind the `specclaw-review` CLI, a stdio MCP server
  (`mcp/server.py`, `.mcp.json`) and a `PreToolUse` guard (`hooks/guard-memory`). Rule packs live in
  `review-rules/`, mirroring `presets/`. Repo rules live in `.specclaw/review/rules/`. Review memory lives in
  `.specclaw/review-memory/findings.jsonl`, reached only through the MCP server or CLI. `discover` + the
  `rules` skill set a repo up from its own governance and review history. Core `verify`/`pr`
  call it behind `command -v`.
- `plugins/specclaw/bin/` — executable Bash lifecycle rules; skills call these helpers rather
  than reimplementing mechanics.
- `plugins/specclaw/bin/specclaw-presets` — the only preset resolver (change 045). It prints resolved
  preset paths, `base` first. A project's `.specclaw/presets/<name>.md` replaces the built-in of the
  same name; a local-only name adds one. `extends: <name>` in leading frontmatter only keeps the parent
  first, one level. The lean build skill reads its output and stops on non-zero exit.
- `plugins/specclaw/lib/pr-git.sh` — the PR git steps (branch check, TTY guard, lock-excluding
  staging, branch publish, post-PR bookkeeping commit), sourced by `specclaw-pr` and
  `specclaw-azdo-pr` (specclaw-sync) so neither carries an inline copy.
- `plugins/specclaw/skills/` — canonical lifecycle `SKILL.md` tree shared by Claude and installed
  Codex users.
- `plugins/specclaw/.claude-plugin/plugin.json` — Claude package metadata.
- `plugins/specclaw/.codex-plugin/plugin.json` — native Codex manifest; its `skills` field exposes
  `./skills/` directly, with no copied lifecycle implementation.
- `.agents/plugins/marketplace.json` — repository-root Codex marketplace catalog. Its
  `./plugins/specclaw` source is resolved from the checkout root for `codex plugin marketplace add`
  and `codex plugin add` installation.
- `.agents/skills/specclaw/SKILL.md` — checkout-local Codex adapter. It dynamically resolves the
  checkout root and delegates lifecycle verbs to canonical assets; it owns no implementation/state.
- `plugins/specclaw/templates/` — seed files for a project's `.specclaw/`, including `context.md`.
- `plugins/*/tests/` — Bash test suites, all registered in `.github/workflows/ci.yml`.
- `.specclaw/` — per-project durable record: `config.yaml`, `context.md`, `STATUS.md`, and
  `changes/<NNN>-<slug>/` artifacts. Active phase dispatches temporarily use `.lock/meta.json`.
  Completed changes move to `changes/archive/<NNN>-<slug>/`; `party/session-spawns.jsonl` is a
  separate top-level cross-change ledger.

Change folders carry permanent three-digit ordinals assigned by `specclaw-next-change-number` and
preserved through archival. `specclaw-update-status` and `specclaw-reconcile` iterate them in
numeric order, with unnumbered legacy folders after numbered ones.

**Per-change dispatch lock.** `plan`, `build`, `verify`, and `pr` acquire
`changes/<change>/.lock/meta.json` through `specclaw-change-lock` before mutation and release it
on completion. Staleness uses wall-clock age only (`git.lock_stale_minutes`, default 120), not PID
liveness; a dispatch spans separately invoked processes and has no meaningful single PID. Lock
directories are never committed: `specclaw-ensure-init` backfills the `.lock/` ignore rule into
older projects, and `specclaw-check-staged` flags any staged lock path as `suspicious`.

**A change reaches the base through its PR.** `specclaw-build finalize` runs checks, records the
build and leaves the branch checked out (`"merged": false`); it merges and deletes the branch only
when `git.merge_on_finalize: true` (default `false`).

## Coding Style & Conventions

- **Scripts are Bash + coreutils.** `jq` and `python3` may be used in `bin/`; test suites stay
  jq-free (`run-parser-tests.sh` is the exception and shells out to it).
- **Every test suite must be registered in `.github/workflows/ci.yml`.** An unregistered suite
  silently never runs.
- **Tests and fixtures live in the plugin that owns the script under test.** Core's
  `plugins/specclaw/tests/` never runs an add-on's `bin/`; brownfield collector cases and their
  `analyze/` and `rebuild-plan/` fixtures live in `plugins/specclaw-bf/tests/`.
- **Native Codex packaging has a focused CI gate.** `tests/run-codex-plugin-tests.sh` validates
  marketplace and manifest JSON, marketplace-root path resolution, Claude/Codex metadata parity,
  declared skill root, canonical skill inventory, and CI registration. It stays offline and never
  mutates global Codex configuration.
- **The checkout-local adapter has a separate focused gate.** `tests/run-codex-skill-tests.sh`
  validates CI registration, root resolution, dynamic routing, and the one-file boundary.
- **`tests/shellcheck-gate.sh` passes with `shellcheck-baseline.txt` unchanged.** Fix new findings
  or add a targeted `# shellcheck disable=SCxxxx` with a written rationale.
- **Force base ten for digit runs read from disk:** `$((10#$n))`; `$((08))` is invalid Bash.
- **Quote every path; never interpolate a change name into a regex.** Change names are opaque and
  are tested against shell/regex metacharacters.
- **Version bump before every PR:** Claude and Codex manifests must remain in sync. `specclaw-pr`
  auto-bumps their patch version when `plugin.version_files` says the base version is unchanged.
- **Hand-written Bash JSON must escape values.** `specclaw-party`'s `json_str` and
  `specclaw-change-lock`'s `json_esc` escape backslashes/quotes before interpolation.
- **Azure DevOps PR descriptions have a character budget.** `specclaw-azdo-pr`'s `fit_description`
  keeps the description ≤ `azdo.pr_description_max` (default 3900, floor 1000; ADO rejects > 4000).
  Sections shrink lowest-value first (time accounting → staged files → verify excerpt → tests →
  acceptance criteria → summary). Each is cut at a newline and ends in a pointer into the change dir.
  The verdict line and footer are outside every shrinkable body. Under-budget output is
  byte-identical to the pre-041 format, pinned by `tests/fixtures/azdo-pr-description/small.golden`.
- **Git steps shared by both PR scripts live in `lib/pr-git.sh`.** Fix them there, not per script;
  `tests/run-headless-pr-tests.sh` drives the real scripts with a stub `gh`, a local bare `origin`
  and no controlling terminal (a hang shows as exit 124).
- Where a helper must be duplicated between standalone executables, copies stay byte-identical and
  a test pins that identity.

## Key Patterns

- **Native package metadata, canonical implementation.** The Codex marketplace selects the
  existing `plugins/specclaw` root and its manifest points at `./skills/`; packaging never copies
  skills, binaries, templates, or references.
- **Derived, not stored.** Recompute facts already on disk instead of caching them. For example,
  `specclaw-next-change-number` takes the current maximum ordinal plus one.
- **One writer per state file.** `specclaw-set-phase` alone writes `changes/<change>/state.json`.
  It writes atomically and callers must preserve every carried field when refreshing a record.
- **Anchor dispatch locks at a true dispatch boundary.** Do not add lock acquisition to a `bin/`
  subcommand that may also be a standalone read-only inspection; acquire in the phase `SKILL.md`
  boundary and keep only idempotent release in the helper when necessary.
- **Append-only, sum-on-read ledgers for cross-run counts.** `specclaw-timer`'s timeline and
  `specclaw-party`'s session-spawn ledger write one JSON event per line and compute totals on read.
- **Shared counter formats are caller contracts.** When `specclaw-parse-tasks --count` gained its
  deferred fourth field, every caller and its zero fallback changed together; `read` otherwise
  silently appends surplus fields to the last variable.
- **Plan → validate → execute destructive work.** Refuse before the first mutation; destructive
  tools such as `specclaw-renumber-changes` are dry-run by default and need `--apply`.
- **Self-clearing hints, not “already asked” flags.** Condition prompts on the live condition so
  they disappear when resolved without extra state.
- **Headless-safe by default.** A script that would prompt checks for a terminal first and, without
  one, exits 2 naming the config key to set (e.g. `pr.test_policy`). A failed `read` also exits 2,
  so a prompt loop can never spin.
- **One resolver, callers read its output.** Build skills never hard-code `presets/` paths; they run
  `specclaw-presets` and treat non-zero exit (unknown or unusable name) as a stop, not a skip.
- **Structured fields come from structure only.** `extends` is read from leading frontmatter; an
  `extends:` line elsewhere only warns.
- **Document fallback precedence** for incomplete data and use deterministic name tiebreakers.
- **`git mv` inside a working tree, plain `mv` outside it.**
- **Mixed old/new states are supported steady states.** No lifecycle command fails merely because
  a folder predates a convention.

## Technology Decisions

- **specclaw-review is python3-stdlib, not Node.** One core library serves the CLI, the stdio MCP server and the
  guard hook; it matches the existing python `bin/` helpers and adds no runtime for Codex users.

- **Opt-in local merge.** `git.merge_on_finalize` (default `false`) keeps today's merge-and-delete
  for users with no PRs; the default leaves the branch for `verify` and `pr`, which need it.
- **Bash + coreutils** ship directly as runnable lifecycle helpers, with no build step/runtime.
- **Codex uses `.agents/plugins/marketplace.json` and `.codex-plugin/plugin.json`.** They provide
  portable Codex discovery metadata over the canonical plugin root while the Claude manifest
  remains its own packaging contract.
- **Offline contract tests, not installation tests, are the CI package gate.** Static validation
  is deterministic and avoids configured marketplaces/plugin caches; any install smoke test must
  use an isolated temporary Codex home.
- **Three-digit change ordinals** (`NNN-<slug>`) preserve lexical chronological order past 99;
  `printf '%03d'` widens above 999 rather than colliding.
- **`^[0-9]+-`, excluding `^[0-9]{4}-[0-9]{2}-[0-9]{2}`, defines numbered folders.** This avoids
  mistaking legacy date-prefixed archives for ordinals.
- **Archive folders retain their ordinal and drop their old archive-date prefix.** The archive date
  belongs in `state.json`.
- **No config key controls numbering format.** It is one fixed rule.
- **Concurrency uses wall-clock staleness, unlike browser-slot PID semaphores.** Their ownership
  models differ even though both use atomic `mkdir` claims.

## Constraints

- **Never treat a review that did not run as clean.** Backend failure or unparsable output is exit 3 /
  `not_run`; parsing never drops a finding; a missing or rebased-away final pass is a not-OK verdict.
- **Never pass a user-supplied ref to git unresolved.** `specclaw-review` resolves `--since` to a commit sha
  first, so it can never reach git as an option.

- **Never write `state.json` directly.** Use `specclaw-set-phase`; omitting a field can delete it.
- **Never add an index/cache for filesystem-derived state.** Append-only event ledgers are distinct.
- **Never silence ShellCheck by appending to `shellcheck-baseline.txt`.**
- **Never add an unregistered test suite.**
- **No GNU-only flags in `bin/` or `tests/`.** Avoid `find -printf`, `stat -c`, suffixless `sed -i`, bare
  `timeout`, and unstripped `wc -l` output (BSD pads it). Use `find … | sed`, `stat -c … || stat -f …`,
  `sed -i.bak` + `rm`, the `timeout` → `gtimeout` → plain/perl-alarm fallback, and `tr -d ' '` on counts.
  CI is Linux-only, so macOS breakage is invisible there; the 046 fixes were two real product bugs
  (`specclaw-run-long`, `specclaw-browser-lock`) plus test bugs.
- **Never copy canonical assets for Codex.** The installed package points at
  `plugins/specclaw/skills/`; the single checkout-local adapter delegates to that same root.
- **Never let package validation mutate global Codex configuration.** Installation tests, if
  needed, must use an isolated temporary Codex home; CI remains offline.
- **Never rename/migrate a user's change folders automatically.** Require explicit `--apply` and
  confirmation; never rename one mid-build.
- **Never assume a change name starts with a letter or has a number.** Do not lexical-sort changes
  where chronology matters or place unnumbered folders first.
- **A `--force` safety override only overrides its documented failure mode.** For example,
  `specclaw-change-lock acquire --force` clears stale locks but still refuses live ones.

- **Never prompt without a terminal.** Exit 2 and name the config key to set.
- **Never `git push … || true`.** Publish failures are hard errors raised before `gh pr create`. Use
  a plain push only when the upstream has the branch's own name; branches cut from `origin/<base>`
  track the base, so otherwise run `push -u <remote> HEAD`.
- **Never commit dispatch locks.** Stage a change dir with `':(exclude)<change>/.lock'`.
- **Never resolve a preset outside its presets dir.** A resolved file must be a regular file inside its
  presets dir; a symlink escape, dangling link or directory is refused with no fallback to the built-in.
  Path-like names are unknown names. Nested extends is reported (a local parent extending its own
  built-in is not nesting).

## Recent Decisions

<!-- Last 5 significant decisions from merged changes. Updated automatically on each PR merge. -->

1. **2026-10-20 — 046-macos-test-portability:** five suites and two `bin/` scripts made BSD/macOS-portable
   by reusing existing idioms (timeout fallback, `tr -d ' '` on counts); a macOS CI job is a separate change.
2. **2026-10-20 — 045-project-custom-presets:** projects keep presets in `.specclaw/presets/<name>.md`; a
   same-name file replaces the built-in, and `extends: <name>` (leading frontmatter only, one level)
   keeps the parent first. `specclaw-presets` is the sole resolver.
3. **2026-10-20 — 045-project-custom-presets:** unusable preset files (symlink escape, dangling link,
   directory) are refused, not silently replaced by the built-in. Review majors (shared scalar parser,
   tab-led comments) were deferred to `follow-ups.md`.
4. **2026-10-16 — 044-fast-review-loop:** PR review runs locally in the `specclaw-review` add-on (review →
   class fix → delta + impact-set round → Opus final pass → one push); CI only checks the reviewed SHA is HEAD.
5. **2026-10-16 — 044-fast-review-loop:** the rulebook is plugin packs + `.specclaw/review/rules/` + the repo's
   own governance read live (`review.governance`), and with governance set the repo's severity policy wins
   (`severity: project`).
