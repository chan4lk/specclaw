# Proposal: Tracker state integrity — one writer, one source of truth for phase

**Created:** 2026-08-01
**Status:** 🟡 Draft

## Problem

Tracker files lie. A change with an open PR still renders as *Build* — the operator reported it, and
the cause is not one oversight but **four independent defects**, two of them reproduced below.

### Evidence in the wild

`keyflow/.specclaw/changes/objective-multi-owner/status.md`, with PR #417 open since 2026-07-30:

```
| Build  | ✅ Done    | 11/11 tasks, `bun run build` passing |
| Verify | ⬜ Pending | —                                     |
```

No PR row at all. `**Last Updated:** 2026-07-30 11:39 UTC`. The file's last honest statement is that
build finished — exactly the "stuck at build" the operator sees.

### Defect 1 — the PR-row insert `sed` matches *every line* (reproduced)

`bin/specclaw-pr:470` (and the twin at `bin/specclaw-azdo-pr`):

```bash
sed_i "/^\|[[:space:]]*Verify[[:space:]]*\|/a\| PR     | ✅ Raised | $url |" "$status_file"
```

`sed` uses BRE, where GNU `\|` is **alternation**, not a literal pipe. So the address reads
`^` OR `[[:space:]]*Verify[[:space:]]*` OR `` — and the empty alternative matches every line.
Run against the real `templates/status.md`:

```
$ sed -i "/^\|[[:space:]]*Verify[[:space:]]*\|/a\| PR ... |" status.md
$ grep -c 'Raised' status.md
33
```

33 PR rows, one after every line in the file, including inside the header. The guard `grep -qE '^\|…'`
above it is correct only because **ERE** treats `\|` as a literal — the same string means two different
things in the test and in the edit.

### Defect 2 — the PR-row update `sed` is syntactically invalid (reproduced)

`bin/specclaw-pr:467`, taken on every subsequent run once a `| PR |` row exists:

```bash
sed_i "s|^\(| *PR *|\).*|\1 ✅ Raised | $url |" "$status_file"
```

The `s` command is delimited by `|`, and the pattern itself contains literal `|` characters. Result:

```
sed: -e expression #1, char 14: unknown option to `s'
```

`specclaw-pr` runs under `set -euo pipefail` (line 5) and `save_pr_url` is called **unguarded** at
line 655, immediately after `gh pr create`. So a non-zero `sed` **aborts the whole script after the PR
already exists**, skipping everything downstream: `specclaw-update-context`, the `STATUS.md`
regeneration, and the issue-sync step. The PR is real; every tracker is frozen at its pre-PR state.
This is the mechanism that makes the failure *silent* — the PR URL gets posted, so it looks like it worked.

### Defect 3 — no source of truth for "phase"; the dashboard infers it from checkboxes

`bin/specclaw-update-status:104-121` derives a change's entire rendered state from `tasks.md` marker
counts:

```bash
status_emoji="🔨"
[ "$failed" -gt 0 ] && status_emoji="⚠️"
[ "$done" -eq "$total" ] && [ "$total" -gt 0 ] && status_emoji="✅"
```

There is no phase concept anywhere in the pipeline — no `state.json`, no `current_phase` field
(grep confirms neither exists). "Verified", "PR raised", and "build finished" are indistinguishable;
🔨 is what a fully-built, PR-open change renders as. `pr_state_for()` partly compensates by querying
`gh pr list --head "${branch_prefix}${change}"`, but that is a *network guess* about local state, and it
silently yields nothing whenever the branch name doesn't match `git.branch_prefix` — this repo's config
says `specclaw/` while `CLAUDE.md` mandates `claude/<short-task>` branches, so the lookup misses here by
construction.

Meanwhile the per-change `status.md` phase rows are written by **three different mechanisms with no
shared contract**: Proposal by skill prose (`skills/propose/SKILL.md:16`), Verify by script
(`bin/specclaw-verify:570-585`), PR by the two broken `sed` calls — and the **Build row by nothing at
all** except an instruction to a model (`skills/build/SKILL.md:100`). Every hand-maintained row drifts.

### Defect 4 — `GOALS.md` has no writer

`grep -rl GOALS plugins/specclaw` returns **zero files**. The `## Proposals` checklist that the
scheduler and the operator both read is maintained entirely by hand. This is why keyflow needed a
110-proposal reconciliation audit that archived 104 already-shipped entries — the drift is not
incidental, it accumulates until someone pays it down manually.

**Common root cause:** phase state is derived, never recorded; and it is edited by regex surgery from
several call sites instead of rendered from one place.

## Proposed Solution

Record phase state once, in a machine-readable file; render every tracker from it; delete the regex
surgery.

**1. `state.json` per change — the single source of truth (new).**

`.specclaw/changes/<change>/state.json`:

```json
{
  "change": "objective-multi-owner",
  "phase": "pr",
  "phases": {
    "proposal": {"status": "approved", "at": "2026-07-29T..."},
    "spec":     {"status": "done",     "at": "..."},
    "build":    {"status": "done",     "at": "...", "tasks": {"done": 11, "total": 11, "failed": 0}},
    "verify":   {"status": "passed",   "at": "...", "verdict": "PASS"},
    "pr":       {"status": "raised",   "at": "...", "url": "https://…/417", "state": "open"}
  },
  "branch": "claude/objective-multi-owner"
}
```

`branch` is **recorded at build time**, so `STATUS.md` never has to guess it from `branch_prefix` —
this alone fixes the silent PR-lookup miss in Defect 3.

**2. `specclaw-set-phase` — the only writer (new `bin/` script).**

```
specclaw-set-phase .specclaw <change> <phase> <status> [--note "…"] [--url …] [--verdict …]
```

Every phase transition goes through it: propose, plan, build (per wave + on completion), verify, pr,
archive. It updates `state.json`, then **re-renders `status.md` wholesale from the template + state** —
no in-place `sed`, so Defects 1 and 2 cease to exist as a class rather than being patched. Idempotent
and monotonic: re-running a transition is a no-op, and a later phase never silently un-sets an earlier one.

**3. Fix the two `sed` bugs immediately, ahead of the refactor.**
`save_pr_url` becomes a `specclaw-set-phase … pr raised --url` call. Until it lands, the two expressions
are replaced with a delimiter that doesn't collide and a literal-pipe address (`[|]`, not `\|`) —
they are shipping corruption today and should not wait for the full design.

Also: **`save_pr_url` must not be able to abort the script after the PR exists.** Anything post-`gh pr
create` is bookkeeping and must be fail-soft with a loud warning, never `set -e` death.

**4. `STATUS.md` renders phase from `state.json`, not from checkbox counts.**
Active-changes rows show real phase (`🔀 pr open`, `🔍 verify`, `🔨 build 7/11`), falling back to the
current inference only when `state.json` is missing — so pre-existing changes keep rendering as they do
now.

**5. `specclaw-reconcile` — drift detector (new subcommand).**
Compares `state.json` against observable reality (`tasks.md` markers, `verify-report.md` presence,
`gh pr view` on the recorded branch, git log) and reports mismatches; `--fix` adopts reality. This is
the keyflow 110-proposal audit as a script instead of an afternoon.

**6. `GOALS.md` gets a writer.** `specclaw-update-status` also syncs the `## Proposals` checklist:
ticked when archived, unticked while active, appended when a proposal appears. One owner, no hand edits.

## Scope

### In Scope
- `state.json` schema + `bin/specclaw-set-phase` as sole writer; `status.md` rendered, never `sed`-patched.
- Immediate fix for both broken `sed` expressions in `specclaw-pr` and `specclaw-azdo-pr`.
- Make all post-`gh pr create` bookkeeping fail-soft (no `set -e` abort after the PR exists).
- Record `branch` in `state.json` at build time; `STATUS.md` uses it instead of `branch_prefix` guessing.
- Phase transitions wired into propose, plan, build, verify, pr, archive.
- `STATUS.md` phase-aware rendering with fallback for changes lacking `state.json`.
- `bin/specclaw-reconcile` (report + `--fix`).
- `GOALS.md` `## Proposals` sync inside `specclaw-update-status`.
- Bats coverage: the 33-row regression, the invalid-`s`-command regression, phase monotonicity,
  reconcile drift cases. Registered in CI; shellcheck-clean.

### Out of Scope
- Timing/duration fields — that is `phase-time-accounting`. This change owns *which* phase, not *how long*.
- Enforcing that PRs open only via `specclaw-pr` — that is `staged-files-auditor` (Layer 3). The two are
  complementary: this one makes the state correct when the script runs; that one makes the script run.
- Backfilling `state.json` for already-archived changes (`reconcile --fix` can, opportunistically).
- Replacing `status.md` as a human-readable artifact, or moving to a database.
- Changing the phase list itself.

## Impact

- **Files affected:** ~12 (estimated) — 2 new `bin/` scripts (`set-phase`, `reconcile`),
  `specclaw-pr`, `specclaw-azdo-pr`, `specclaw-build`, `specclaw-verify`, `specclaw-update-status`,
  `specclaw-archive`, 3 SKILL.md updates, `templates/status.md`, 1 new bats suite.
- **Complexity:** medium — schema and renderer are simple; the work is replacing scattered edits with
  one writer without breaking the format that `gh-sync`, `azdo-issue`, and `jira-issue` already parse
  out of `status.md` (they grep it for issue/PR lines — the renderer must keep those lines intact).
- **Risk:** low-to-medium. The `sed` fixes are strictly corrective — the current behaviour is a proven
  bug. The refactor's real risk is *format churn* breaking the three integration scripts that grep
  `status.md`; mitigate by pinning the rendered format in a bats golden file and reading those greps
  first. Fail-open throughout: a missing or malformed `state.json` must degrade to today's behaviour,
  never block a phase.

## Open Questions

1. **Ship the two `sed` fixes as a separate hotfix PR first?** They are corrupting `status.md` in every
   repo running specclaw right now, independent of the rest of this design. Recommend yes.
2. Is `state.json` **committed** (reviewers see phase in the PR diff, but it churns every transition) or
   gitignored with `status.md` as the committed rendering?
3. **How much does `reconcile` trust the network?** `gh pr view` failing offline must read as "unknown",
   never as "no PR" — the latter would let `--fix` regress a correct state.
4. Does the rendered `status.md` need to be **byte-stable** for unrelated transitions, to keep PR diffs
   small? That constrains the renderer (stable ordering, no timestamp churn in untouched rows).
5. **Should `phase` be strictly ordered** (proposal→…→pr→archived) with illegal transitions rejected, or
   a free-form label? Strict catches bugs; free-form survives non-linear reality like re-verify after a
   loop fix.
6. `GOALS.md` is also written by the mcd bot's `backlogWatch` (it tracks `{done, total}` snapshots per
   channel). Does specclaw owning the checklist **collide** with that? Needs checking before wiring.

---

**To proceed:** Review this proposal and approve to begin planning.
