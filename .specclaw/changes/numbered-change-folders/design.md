# Design: Numbered change folders

**Change:** numbered-change-folders
**Created:** 2026-08-08

## Technical Approach

Two new scripts in `plugins/specclaw/bin/`, a sort function threaded into two existing scripts, and skill-markdown wiring. No new state, no new config, no schema change.

The organising principle is that **the number lives in exactly one place — the directory name** — and everything else derives from it. There is no counter file, because a counter file is a second source of truth that can drift from the filesystem, and this repo has spent two changes (#57, and the status-row work before it) removing exactly that class of duplication.

### 1. `specclaw-next-change-number <specclaw_dir>`

Globs `changes/*/` and `changes/archive/*/`, takes `basename`, matches `^[0-9]+`, tracks the maximum, prints `max + 1` via `printf '%03d'`.

Three details carry the whole script:

- **Base ten is forced everywhere.** `$((08))` is a bash syntax error, not a zero — a folder named `008-foo` would abort the script under arithmetic evaluation. Every comparison uses `$((10#$n))`. This is the defect most likely to ship, so it gets a dedicated acceptance criterion (AC4) rather than a comment.
- **Non-matching names are skipped, not rejected.** Mixed numbered/unnumbered is a supported steady state (FR5, NFR5). An unnumbered repo that never runs the backfill must keep working forever.
- **`printf '%03d'` widens rather than truncates** at 1000. The format string is a minimum width, so overflow degrades to a longer name rather than a collision.

### 2. `specclaw-renumber-changes <specclaw_dir> [--apply] [--force]`

A three-phase script: **plan → validate → execute.** Nothing touches the filesystem until every check has passed, which is what makes the failure mode "stopped early" instead of "clobbered halfway".

**Plan.** For each folder under `changes/` and `changes/archive/`, resolve a sort date by falling through four sources in order:

| Precedence | Source | Covers |
|---|---|---|
| 1 | `**Created:**` in `proposal.md` | 29 of 30 folders in this repo |
| 2 | `git log --diff-filter=A --reverse` on the folder | `git-worktrees`, whose proposal has no `Created:` line |
| 3 | leading `YYYY-MM-DD-` on the folder name | old-style archives with no proposal at all |
| 4 | sorts last | partially-created folders |

Ties break by folder name, so repeated runs produce identical output (AC10). The new name is `<NNN>-<slug>`, where `<slug>` is the old name with any leading `YYYY-MM-DD-` stripped — otherwise the backfill would produce `014-2026-07-22-build-engine` and preserve the misleading prefix this change exists to remove.

**Validate.** Three refusals, all before any move:

- any folder already numbered → refuse unless `--force` (FR11)
- any change mid-build, detected via `git worktree list` and the current branch → refuse (FR12)
- any planned target already exists → refuse (FR13)

**Execute.** Only with `--apply`. `git mv` inside a working tree, `mv` outside it. After each rename, if the folder has a `state.json`, refresh its `change` field by re-invoking `specclaw-set-phase` at the change's *current* phase and status.

That last point is the design's one genuinely non-obvious decision, so it is spelled out below.

### 3. Why the rename refreshes `state.json` through `set-phase`

`state.json` records `"change": "<name>"`. After a rename that label is stale.

The tempting fix — a one-line `sed` on the file — is exactly what `plugins/specclaw/CLAUDE.md` forbids: *"Nothing else may write it — not a script, not a skill, not the model editing status.md prose."* That rule exists because phase state previously had six writers that regularly disagreed.

So the rename re-invokes the sanctioned writer instead:

```
specclaw-set-phase "$specclaw_dir" "$new_name" "$phase" "$status"
```

reading `phase` and `status` back from the existing file first. Three properties make this safe rather than clever:

- **Equal-rank transitions are explicitly allowed** by `set-phase` (re-running verify is normal), so no `--force` is needed and no monotonicity guard is tripped.
- **`at` timestamps are preserved** when a record is otherwise unchanged — `set-phase`'s documented idempotency rule 3 — so the refresh does not rewrite history with a meaningless fresh timestamp.
- **The write is atomic** (temp file → parse check → `mv`), so an interrupted refresh cannot corrupt the file.

Planning confirmed this is a correctness nicety, not a functional requirement: **no script in `bin/` reads the `change` field.** It is written by `set-phase` and `specclaw-verify` purely as provenance. Had it been load-bearing, the backfill would have needed a lockstep update and a far heavier risk story; it is not, so the field is refreshed because a durable record should not carry a stale label, and for no other reason.

### 4. Numeric ordering in `update-status` and `reconcile`

Both scripts currently iterate `for d in "$DIR"/*/`, which is lexical: `010-a` before `002-b`. Both grow a shared sort — numbered folders ascending by number, unnumbered folders after them by name.

The sort is `sort -t- -k1,1n` style over the basenames, with unnumbered entries emitted into a second pass rather than interleaved. Interleaving them at position zero would put legacy folders *first*, which is the opposite of what a reader expects while a repo is mid-migration.

### 5. Skill wiring

| Skill | Change |
|---|---|
| `propose` | Step 1 calls `specclaw-next-change-number` and prepends. Plus the one-time backfill offer (FR18). |
| `archive` | Step 4 drops the `YYYY-MM-DD-` prefix from the target path. |
| `status` | Surfaces the hint line from `update-status` (FR17). |
| `renumber` (new) | Wraps `specclaw-renumber-changes`: dry-run, show plan, confirm, apply. |

The hint and the offer are both conditioned on unnumbered folders existing, which is why neither needs an "already asked" flag — they self-clear when the backfill runs. That is a deliberate avoidance of new state, consistent with the rest of this design.

## File Changes Map

| File | Action | Why |
|---|---|---|
| `plugins/specclaw/bin/specclaw-next-change-number` | create | FR1–FR5 |
| `plugins/specclaw/bin/specclaw-renumber-changes` | create | FR8–FR15 |
| `plugins/specclaw/bin/specclaw-update-status` | modify | FR16, FR17 — numeric sort + hint line |
| `plugins/specclaw/bin/specclaw-reconcile` | modify | FR16 — numeric sort |
| `plugins/specclaw/skills/propose/SKILL.md` | modify | FR6, FR18 |
| `plugins/specclaw/skills/archive/SKILL.md` | modify | FR7 |
| `plugins/specclaw/skills/status/SKILL.md` | modify | FR17 |
| `plugins/specclaw/skills/renumber/SKILL.md` | create | FR19 |
| `plugins/specclaw/tests/run-change-numbering-tests.sh` | create | AC1–AC18 |
| `.github/workflows/ci.yml` | modify | NFR3 — register the suite |
| `plugins/specclaw/CLAUDE.md` | modify | document both scripts in the script table |
| `README.md`, `docs/index.md` | modify | update shown `changes/<name>/` paths |
| `plugins/specclaw/.claude-plugin/plugin.json` | modify | version bump |
| `.claude-plugin/marketplace.json` | modify | version bump, kept in sync |

## Key Decisions

1. **Three digits, not two.** Two digits fails *silently* — `100-foo` sorts before `99-foo` — which would break the exact ordering this change delivers. One extra character removes the failure mode entirely.
2. **Derived, not stored.** The next number is computed from the filesystem on every call. A counter file would be a second source of truth and could drift.
3. **Backfill is offered, never imposed.** Upgrading specclaw renames nothing in a user's repo. Dry-run is the default and `--apply` is required.
4. **Mixed numbering is supported, not an error.** A user who never backfills keeps a fully working repo indefinitely.
5. **`set-phase` stays the only `state.json` writer.** The rename reuses it rather than adding a seventh writer.
6. **Plan → validate → execute, with all refusals before the first move.** Partial renames are the one genuinely destructive outcome here.
7. **Unnumbered folders sort last, not first.** Matches what a reader expects mid-migration.

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Octal parse on `08`/`09` folder names aborts a script | high likelihood, low blast | `10#` everywhere; AC4 pins it |
| `--apply` interrupted, leaving mixed state | low likelihood, medium blast | collision pre-check; FR11 refuses the re-run; `--force` documented as recovery |
| Rename while a build holds a worktree | low likelihood, high blast | FR12 refuses outright |
| A third persistence site for the change name is missed | low | grep found only `state.json` and `verify-report`, neither read; AC14 runs `reconcile` post-backfill as the backstop |
| Skill markdown drifts from script behaviour | medium | the number rule lives only in `next-change-number`; skills call it rather than reimplementing the format |

## Grounding sources

- `plugins/specclaw/CLAUDE.md` — *"Each change's phase lives in `changes/<change>/state.json`. **Nothing else may write it** — not a script, not a skill, not the model editing `status.md` prose."* Directly determines decision 5: the backfill re-invokes `specclaw-set-phase` rather than editing `state.json`.
- `plugins/specclaw/CLAUDE.md` — *"every one must be registered in `.github/workflows/ci.yml` — an unregistered suite silently never runs, which has happened twice."* Makes CI registration part of the test task (NFR3), not a follow-up.
- `plugins/specclaw/CLAUDE.md` — *"Fix a new finding or add a targeted `# shellcheck disable=SCxxxx` with a rationale — never silence one by appending to the baseline."* Sets NFR2's phrasing.
- `plugins/specclaw/CLAUDE.md` — *"Suites live in `tests/`, are bash + coreutils only (no jq in the suites themselves...)"* Sets NFR1's split: `jq` allowed in `bin/`, not in the new suite.
- `plugins/specclaw/bin/specclaw-set-phase:36` — *"Monotonic, not strict. Phases may be re-entered (re-verify after a loop fix is normal); only a move to a *lower* rank is refused."* Confirms the FR15 refresh needs no `--force`.
- `plugins/specclaw/bin/specclaw-set-phase:32` — *"`at` is *preserved* when the rest of the record is unchanged: idempotency (FR3) beats a fresh-but-meaningless timestamp."* Confirms the refresh will not churn timestamps.
- `CLAUDE.md` (repo root) — *"Always bump the plugin version before opening a PR... Both files must stay in sync."* Puts the version bump in the task list rather than leaving it to PR time.
