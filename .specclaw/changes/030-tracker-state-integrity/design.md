# Design: Tracker state integrity

**Change:** tracker-state-integrity
**Created:** 2026-08-01
**Spec:** `.specclaw/changes/tracker-state-integrity/spec.md`

## Technical Approach

Two layers, one writer:

```
                    specclaw-set-phase          ← the only writer
                     /                \
            state.json                 specclaw-status-row → status.md
         (machine truth)                    (human artifact, row upsert)
                    \
                     └── read by ── specclaw-update-status → STATUS.md
                                    specclaw-reconcile     → drift report
```

The proposal called for `status.md` to be **re-rendered wholesale** from template + state. This
design does not. PR #52 shipped `bin/specclaw-status-row`, an idempotent awk upsert that replaces a
row in place, collapses duplicates, and leaves the rest of the file byte-identical. Re-rendering
would rewrite lines that three integration scripts grep for (NFR1), buying format-churn risk for no
gain. Row upsert reaches the same end state — status.md always agrees with state.json — with a
strictly smaller blast radius, and it makes the proposal's open question 4 (byte-stability)
disappear rather than needing enforcement.

`state.json` is written atomically: build the new document in `$(mktemp)`, validate it parses, then
`mv` over the target. A crash mid-write leaves the old file intact (Edge case 3).

## Architecture

### `state.json` schema

```json
{
  "change": "tracker-state-integrity",
  "phase": "build",
  "branch": "claude/tracker-state-integrity",
  "phases": {
    "proposal": {"status": "approved", "at": "2026-08-01T06:00:00Z"},
    "spec":     {"status": "done",     "at": "2026-08-01T06:40:00Z"},
    "build":    {"status": "done",     "at": "...", "tasks": {"done": 7, "total": 7, "failed": 0}},
    "verify":   {"status": "passed",   "at": "...", "verdict": "PASS"},
    "pr":       {"status": "raised",   "at": "...", "url": "https://…/57", "state": "open"}
  }
}
```

Phase order, used for the monotonicity check (FR3):
`proposal < spec < design < tasks < build < verify < pr < archived`.
Rank comparison only — a transition to a *lower* rank than `phase` is rejected without `--force`;
equal rank is always allowed (re-verify, Edge case 10).

### Phase → `status.md` row mapping

`set-phase` translates each transition into one `specclaw-status-row <file> <label> <text> [note]`
call. Labels match the existing template rows (`Proposal`, `Spec`, `Design`, `Tasks`, `Build`,
`Verify`) plus `PR`, which `specclaw-status-row` inserts after the last table row when absent.

### Reading state without a hard `jq` dependency

Reads go through one helper, `state_field <file> <jq_path>`, which uses `jq` when present and a
minimal `python3 -c` fallback otherwise. Both are already CI dependencies (`ci.yml` installs `jq`;
the manifest job uses `python3`). Any read failure returns empty → callers take the FR7 fallback
path.

## File Changes

| File | Change |
|------|--------|
| `plugins/specclaw/bin/specclaw-set-phase` | **new** — the sole phase writer: validate args, read/merge state, atomic write, delegate row upsert |
| `plugins/specclaw/bin/specclaw-reconcile` | **new** — drift report + `--fix` |
| `plugins/specclaw/bin/specclaw-update-status` | read `state.json` for phase and branch; keep the checkbox inference as fallback (FR6, FR7) |
| `plugins/specclaw/bin/specclaw-build` | record `branch` and build completion via `set-phase` (FR4) |
| `plugins/specclaw/bin/specclaw-verify` | replace the hand-rolled Verify-row rewrite (`:570-610`) with `set-phase … verify` |
| `plugins/specclaw/bin/specclaw-pr` | `save_pr_url` → `set-phase … pr raised --url`, fail-soft (FR9) |
| `plugins/specclaw/bin/specclaw-azdo-pr` | same treatment as `specclaw-pr` |
| `plugins/specclaw/skills/{propose,plan,build,verify,archive}/SKILL.md` | call `set-phase` at each transition instead of instructing the model to edit prose (FR5) |
| `plugins/specclaw/tests/run-phase-state-tests.sh` | **new** — suite for set-phase, fallback rendering, reconcile |
| `.github/workflows/ci.yml` | register the new suite |
| `plugins/specclaw/tests/shellcheck-baseline.txt` | only if a pre-existing finding moves line numbers — no new findings permitted |

## Key Decisions

1. **Row upsert over wholesale re-render.** See Technical Approach. Smaller diff, no format churn,
   reuses a helper that already has 26 assertions behind it.
2. **Monotonic, not strict, transitions.** Strict ordering would reject legitimate re-verify loops.
   Rank comparison with `--force` catches the actual bug class (silent regression) at a fraction of
   the friction.
3. **Fail-open everywhere.** Every read of `state.json` degrades to current behaviour on any error.
   A tracker bug must never become a lifecycle blocker — that would trade a cosmetic failure for a
   functional one.
4. **`branch` recorded, never computed.** The `${branch_prefix}${change}` guess is wrong in this very
   repo (`config.yaml` says `specclaw/`, `CLAUDE.md` mandates `claude/<short-task>`). Recording it
   at build time is a one-line fix to a whole class of silent misses.
5. **GOALS.md cut.** Two writers, the other one external and untestable here. Shipping a
   half-understood second writer to an untracked file is how the drift got here.
6. **Depends on PR #52.** Branch from `claude/fix-status-row-sed`, or wait for it to merge.

## Risks

| Risk | Mitigation |
|------|-----------|
| Format churn breaks `gh-sync` / `jira-issue` / `azdo-issue` greps | Row upsert never touches other lines; AC4 asserts the `GitHub Issue` line survives a PR transition |
| `state.json` and `status.md` diverge | One writer, both written in the same call; `reconcile` detects any divergence that still happens |
| Regression in `STATUS.md` for changes without state | AC6 pins byte-identical output against the current implementation |
| `--fix` regressing correct state from a network miss | `unknown` is never actionable; AC10 |
| #52 not merging | Whole design rests on `specclaw-status-row`; re-cut the plan if that happens |

## Grounding sources

`specclaw-discover-context` is unavailable in this install (the cached binary is not executable:
`Permission denied`), and no `.specclaw/context.md` or `.specclaw/knowledge/` exists. Grounding is
therefore direct source reading:

- **`CLAUDE.md`** — "Always bump the plugin version before opening a PR." Both
  `plugins/specclaw/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must move
  together; the CI `json` job enforces the match.
- **`CLAUDE.md`** — branch naming: "`claude/<short-task>` or `<operator-handle>/<topic>`", which is
  the concrete conflict with `git.branch_prefix: specclaw/` behind Key Decision 4.
- **`plugins/specclaw/bin/specclaw-status-row`** (PR #52) — "Idempotent: re-running with the same
  values leaves the file byte-identical." The guarantee Key Decision 1 rests on.
- **`plugins/specclaw/tests/run-status-row-tests.sh`** (PR #52) — "Plain bash + coreutils only",
  `pass`/`fail` counters, `mktemp -d` workdir. The house test style (NFR4).
- **`.github/workflows/ci.yml`** — suites are registered as explicit named steps under the
  "Parser regression suite" job; a new suite is invisible to CI until added there.
- **`plugins/specclaw/bin/specclaw-verify:541-557`** — the existing self-heal-from-template pattern
  `set-phase` reuses for Edge case 4.
