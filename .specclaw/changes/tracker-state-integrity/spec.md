# Spec: Tracker state integrity — one writer, one source of truth for phase

**Change:** tracker-state-integrity
**Created:** 2026-08-01
**Status:** 🟡 Draft
**Proposal:** `.specclaw/changes/tracker-state-integrity/proposal.md` · GitHub Issue #56

## Summary

Phase state is currently *derived* (from `tasks.md` checkbox counts and a network `gh pr list`
guess) and *edited from several call sites* rather than recorded once. The result is trackers that
lie: a change with an open PR renders as 🔨 build.

This change records phase in a machine-readable `state.json` per change, makes
`bin/specclaw-set-phase` the only writer, and has every renderer read from it — with a fallback to
today's inference so pre-existing changes keep working.

## Assumptions & resolved open questions

The proposal left six open questions. Resolved as follows; each is a decision this spec commits to,
not a guess left to the builder.

| # | Question | Resolution | Evidence |
|---|----------|------------|----------|
| 1 | Ship the two `sed` fixes as a separate hotfix first? | **Already done.** PR #52 landed `bin/specclaw-status-row` (idempotent awk row upsert, self-heals duplicated rows) and rewired `specclaw-pr` / `specclaw-azdo-pr` to it. Defects 1 and 2 are **out of scope here**. This change branches off #52. | `git show origin/claude/fix-status-row-sed:plugins/specclaw/bin/specclaw-status-row` |
| 2 | Is `state.json` committed or gitignored? | **Committed.** Everything under `.specclaw/` is tracked; `.gitignore` excludes only `.specclaw/.env` (line 6) and `.specclaw/.update-check` (line 8). A gitignored state file would also be invisible to CI and to reviewers. | `.gitignore:6,8` |
| 3 | How much does `reconcile` trust the network? | A failed or unavailable `gh` call yields **`unknown`**, never `no PR`. `--fix` refuses to act on `unknown` and exits reporting what it skipped. | Proposal Q3 — a network miss must never let `--fix` regress correct state |
| 4 | Must the rendered `status.md` be byte-stable? | **Moot, by design.** Because `specclaw-set-phase` upserts a single row via `specclaw-status-row` rather than re-rendering the file from the template, untouched rows are never rewritten. Byte-stability is a property of the approach, not a constraint to enforce. | `specclaw-status-row` header comment: "Idempotent: re-running with the same values leaves the file byte-identical." |
| 5 | Strictly ordered phases, or free-form? | **Monotonic, not strict.** A phase may be re-entered (re-verify after a loop fix is normal), but a *backward* transition — `pr` → `build` — is rejected unless `--force` is passed. Catches the bug class without breaking non-linear reality. | Proposal Q5 |
| 6 | Does specclaw owning `GOALS.md` collide with the mcd bot? | **Yes — so Defect 4 is cut from this change.** `GOALS.md` is untracked (`git ls-files GOALS.md` → 0) and carries a `## Scheduling` block with the bot's own `Last updated` timestamp, i.e. an active external writer whose behaviour cannot be tested from this repo. Deferred to its own change. | `GOALS.md:3-7`; `git ls-files GOALS.md` |

Further assumption: **`specclaw-status-row` exists.** Every design decision below depends on PR #52
being merged first. If #52 is abandoned, this plan must be re-cut.

## Functional Requirements

**FR1 — `state.json` is the recorded phase.**
Each change may have `.specclaw/changes/<change>/state.json` holding `change`, `phase` (the current
phase), a `phases` map of per-phase `{status, at}` records, and `branch`. It is valid JSON, written
atomically (temp file + move), and never partially written.

**FR2 — `specclaw-set-phase` is the only writer.**
`specclaw-set-phase <specclaw_dir> <change> <phase> <status> [--note S] [--url U] [--verdict V]
[--branch B] [--tasks done/total/failed] [--force]` updates `state.json` and then upserts the
matching human row in `status.md` by delegating to `specclaw-status-row`. No other script writes
phase rows by regex.

**FR3 — Transitions are idempotent and monotonic.**
Re-running the same transition leaves both files byte-identical and exits 0. A transition to an
earlier phase than the recorded one is rejected with a non-zero exit and a clear message, unless
`--force` is given. Re-entering the *current* phase (verify → verify) is always allowed.

**FR4 — The branch is recorded at build time.**
`specclaw-build` records the real branch name into `state.json`. Renderers use it instead of
computing `${branch_prefix}${change}` — the guess that silently misses whenever branch naming
diverges from `git.branch_prefix`.

**FR5 — Every lifecycle phase transition routes through `specclaw-set-phase`.**
Propose, plan, build (on completion), verify, pr, and archive each record their phase. The Build
row in particular stops depending on a model remembering to edit prose.

**FR6 — `STATUS.md` renders real phase.**
`specclaw-update-status` reads `state.json` for each change and renders the recorded phase
(`🔀 pr open`, `🔍 verify`, `🔨 build 7/11`). PR lookup uses the recorded branch.

**FR7 — Missing or malformed `state.json` degrades to today's behaviour.**
Absent, unreadable, or invalid-JSON state must produce exactly the current checkbox-inference
rendering — never an error, never a blocked phase transition.

**FR8 — `specclaw-reconcile` reports drift.**
`specclaw-reconcile <specclaw_dir> [<change>] [--fix]` compares `state.json` against observable
reality (`tasks.md` markers, `verify-report.md` presence, `gh pr view` on the recorded branch) and
prints a per-change drift report. `--fix` adopts reality, skipping anything it could not observe.

**FR9 — Post-`gh pr create` bookkeeping is fail-soft.**
No bookkeeping step after the PR exists may abort the script under `set -e`. Failures warn loudly
and continue. (PR #52 addressed the two known aborts; this change must not reintroduce the class
when routing `save_pr_url` through `specclaw-set-phase`.)

## Non-Functional Requirements

**NFR1 — Format compatibility.** `specclaw-gh-sync`, `specclaw-jira-issue`, and `specclaw-azdo-issue`
grep `status.md` for `GitHub Issue` / `Jira Issue` / Work Item lines
(`specclaw-gh-sync:252,651,706`, `specclaw-jira-issue:170-186`, `specclaw-azdo-issue:46,168-180`).
Those lines must survive every phase transition untouched.

**NFR2 — Dependencies.** Bash + coreutils + `awk`. `jq` may be used (CI installs it; the parser
suite already depends on it) but `state.json` reads must not *require* a `jq` version newer than
what CI provides.

**NFR3 — Lint and CI.** All new/changed scripts pass `plugins/specclaw/tests/shellcheck-gate.sh`
with no new findings. The new test suite is registered as a step in `.github/workflows/ci.yml`.

**NFR4 — Test style.** Plain bash + coreutils harness matching
`tests/run-status-row-tests.sh` (`pass`/`fail` counters, `mktemp -d` workdir, non-zero exit on
failure). Not bats — despite the proposal's wording, this repo has no bats suites.

**NFR5 — Offline safety.** Every `gh` invocation is guarded; no code path blocks or fails when the
network or `gh` auth is unavailable.

## Acceptance Criteria

- **AC1** — `specclaw-set-phase … build done` on a change with no `state.json` creates valid JSON
  with `phase: "build"` and a `phases.build` record.
- **AC2** — Running the identical `set-phase` command twice leaves `state.json` and `status.md`
  byte-identical (`cmp` clean) and exits 0 both times.
- **AC3** — `set-phase … build done` on a change already at `phase: "pr"` exits non-zero, changes
  nothing, and prints a message naming both phases. With `--force` it succeeds.
- **AC4** — After `set-phase … pr raised --url U`, `status.md` contains exactly one `| PR |` row
  carrying `U`, and the `GitHub Issue` line is still present and unmodified.
- **AC5** — A change whose `state.json` records `phase: "pr"` renders in `STATUS.md` as PR-in-review,
  not as 🔨 build, **with `gh` unavailable** — proving the render no longer depends on a network guess.
- **AC6** — A change with no `state.json` renders in `STATUS.md` byte-identically to the current
  implementation's output for the same inputs.
- **AC7** — A change with a corrupt `state.json` (truncated / not JSON) renders via fallback, exits
  0, and emits a warning on stderr.
- **AC8** — `specclaw-build` writes the actual branch name into `state.json`; a change whose branch
  does not match `git.branch_prefix` still resolves its PR.
- **AC9** — `specclaw-reconcile` on a change whose `state.json` says `build` but whose `tasks.md` is
  fully checked and `verify-report.md` exists reports drift and exits non-zero; `--fix` advances the
  state and exits 0.
- **AC10** — `specclaw-reconcile --fix` with `gh` unavailable reports the PR dimension as `unknown`,
  does **not** clear a recorded PR, and says what it skipped.
- **AC11** — `save_pr_url` failing internally does not abort `specclaw-pr` after `gh pr create`
  succeeded; the URL is still reported to the user and a warning is printed.
- **AC12** — `bash plugins/specclaw/tests/shellcheck-gate.sh` passes; the new suite runs green in CI.

## Edge Cases

1. **No `state.json`, no `tasks.md`, but a PR exists** — current code renders `🔀 <pr state>`; must
   stay.
2. **`state.json` present but `phases` empty** — treated as "phase recorded, no history"; render the
   `phase` field, don't crash.
3. **Concurrent writers** — two `set-phase` calls racing on one change. Atomic temp-file + `mv`
   means the loser's write is lost but the file is never corrupt. Documented, not locked.
4. **`status.md` absent when `set-phase` runs** — self-heal from the template, as
   `specclaw-verify:541-557` already does.
5. **`status.md` has no Progress table** — `specclaw-status-row` falls back to a standalone
   `**<label>:** …` line; `set-phase` must not treat that as failure.
6. **A `status.md` already corrupted by the old sed (33 PR rows)** — the first `set-phase` collapses
   them to one; that is `specclaw-status-row`'s documented self-heal.
7. **Archived change** — `state.json` travels with the directory into `archive/`; renderers must not
   choke on state files under `archive/`.
8. **Phase name not in the known list** — reject with a usage error listing valid phases, rather
   than writing an unrenderable state.
9. **`--url` containing shell metacharacters or pipes** — must land in `status.md` intact (the pipe
   case is exactly what broke before).
10. **Re-verify after a loop fix** — `verify → verify` with a changed verdict must be allowed and
    must overwrite the previous verdict.

## Out of Scope

- Timing/duration fields — owned by `phase-time-accounting`.
- Enforcing that PRs open only via `specclaw-pr` — owned by `staged-files-auditor`.
- `GOALS.md` `## Proposals` sync — cut, see Assumption 6.
- The two `sed` fixes — shipped in PR #52.
- Backfilling `state.json` for already-archived changes (`reconcile --fix` may do it opportunistically).
- Replacing `status.md` as the human-readable artifact; changing the phase list itself.
