# Proposal: Staged-files auditor — a gate that verifies exactly what lands in the PR

**Created:** 2026-08-01
**Status:** 🟡 Draft

## Problem

PRs ship the wrong file set in both directions: **planning artifacts go missing**, and **unrelated
junk gets swept in**. Both are silent — nothing checks the branch's file list against what the change
was supposed to touch.

**Missing artifacts — observed repeatedly.** In the keyflow channel the operator reported it three
separate times on one PR: `proposal file is not there`, then `Proposal files are missing in pr`, then
`Proposal files are missing in pr` again after a session rotation.

The mechanism is understood. `specclaw-pr:621-642` *does* stage the whole change dir and *does*
hard-abort if anything is left uncommitted, and `skills/pr/SKILL.md:15` explicitly says **"always
create the PR through this script, never hand-roll `gh pr create`"**. But that instruction is prose
addressed to a model, and there are paths that bypass it:

- keyflow's `🦞 Build Complete` message announced `Branch: … → pushed (not merged)` **and a PR URL in
  the same breath** — a PR opened outside `specclaw-pr`, so the artifact-staging step at line 631 never
  ran. Every guarantee in `specclaw-pr` is unreachable when the PR is created by hand.
- `specclaw-build:294` stages only `git add -- "${files[@]}"` — the files a task *declared*. Anything a
  task touched but forgot to declare is left behind and never noticed.
- After a session rotation the fresh agent has no memory of the pr-skill contract and reaches for
  `gh pr create` directly.

So the correctness of a PR's file list currently depends on a model remembering a sentence.

**Unwanted files — the mirror failure.** `specclaw-loop:936` runs `git add -A` on escalation, and
`skills/loop/SKILL.md:107` documents `git add -A && git commit` as the loop-fix step. `git add -A`
takes whatever is in the tree. This repo's own working tree right now shows exactly what that sweeps
up: eleven `.session-id.rotated-*` files, `watchdog-kills.jsonl`, and an untracked `GOALS.md` — none
of which belong to any change, none gitignored. One escalation commit and they are in the PR.

Root cause, stated once: **there is no verification of the branch's file list against the change's
declared scope.** `specclaw-validate-change` checks that artifact files *exist on disk*; it never asks
whether they are *committed to the branch*, and nothing at all asks whether extra files came along.

## Proposed Solution

Add a two-layer gate before any PR opens: a cheap deterministic check, then a reasoning sub-agent for
the judgement calls that a script cannot make.

**Layer 1 — `specclaw-check-staged` (new `bin/` script, deterministic, fast, no model).**

```
specclaw-check-staged .specclaw <change> [--base <branch>] [--json] [--strict]
```

Diffs `origin/<base>...HEAD` plus `git status --porcelain`, then classifies every path into four buckets:

| Bucket | Rule | Default verdict |
|--------|------|-----------------|
| **required-missing** | Files in the mandatory artifact set (`proposal.md`, `spec.md`, `design.md`, `tasks.md`, `status.md`, `verify-report.md`) absent from the branch diff | **BLOCK** |
| **declared** | Path appears in a `tasks.md` task's file list | OK |
| **undeclared** | Changed in the branch but declared by no task | WARN → agent review |
| **suspicious** | Matches junk patterns (`*.log`, `.session-id*`, `*-kills.jsonl`, `.env*`, lockfile churn with no dep change, files outside the repo's source roots) | **BLOCK** unless allowlisted |

Exit non-zero on any BLOCK. This alone catches every case the operator has actually reported, with no
token spend, and it is the layer `--strict` mode can be trusted to enforce in CI.

**Layer 2 — `staged-files-auditor` sub-agent (new `agents/` definition).**

Layer 1 cannot judge whether an undeclared file is a legitimate ripple (a barrel export updated for a
new module) or genuine scope creep. That is the sub-agent's job. It is spawned by `/specclaw:pr` when
Layer 1 reports anything in the WARN/BLOCK buckets and receives: the classified path list, `spec.md`
scope, `tasks.md` declared file lists, and `git diff --stat`. Tools limited to Read / Grep / Bash
(read-only git). It emits `staged-files-report.md` with one line per flagged path and a verdict:

```
APPROVED | APPROVED_WITH_NOTES | CHANGES_REQUESTED
path: <emoji> <BLOCK|WARN|NOTE>: <why>. <fix>.
```

This mirrors the existing `specclaw:code-reviewer` agent contract (10-dimension review →
`review-report.md` → verdict) so the pattern, the report shape, and the config gate are all consistent
with what the plugin already does — a reviewer for *content* already exists; this is the reviewer for
*file set*.

**Layer 3 — close the bypass, which is the actual fix.**

The gate is worthless if `gh pr create` can still be hand-rolled. Therefore:

- `specclaw-pr` and `specclaw-azdo-pr` call `specclaw-check-staged` before staging and **die on BLOCK**,
  the same way the existing artifact hard-constraint at `specclaw-pr:641` dies.
- `specclaw-build`'s finalize step **must not announce or create a PR**. It ends at "branch pushed —
  run `/specclaw:pr`". This directly removes the keyflow failure path.
- `specclaw-loop`'s escalation commit switches from `git add -A` to a scoped add (the change dir + files
  declared in `tasks.md`), with anything else listed in the escalation note as "left in working tree,
  not committed". Same for `skills/loop/SKILL.md:107`. Preserving partial work must not mean
  committing the whole filesystem.
- Post-commit safety net: after staging, re-run the check and abort if `suspicious` is non-empty.

**Config, so projects can tune it:**

```yaml
workflow:
  staged_files_audit: true       # spawn the auditor agent on /specclaw:pr
  staged_files_block: true       # hard-block the PR on CHANGES_REQUESTED
pr:
  allowed_extra_paths: []        # globs that are always fine undeclared (e.g. CHANGELOG.md)
  junk_patterns: []              # project-specific additions to the suspicious set
```

Mirrors the existing `workflow.code_review` / `code_review_block` pair.

## Scope

### In Scope
- New `bin/specclaw-check-staged` — four-bucket classifier, `--json`, `--strict`, non-zero exit on BLOCK.
- New `agents/staged-files-auditor.md` sub-agent + `staged-files-report.md` output contract.
- `specclaw-pr` / `specclaw-azdo-pr`: run the check pre-staging, die on BLOCK, re-check post-commit,
  spawn the auditor when configured, link the report in the PR body.
- `specclaw-build` finalize: stop creating/announcing PRs; hand off to `/specclaw:pr`.
- `specclaw-loop` escalation + `skills/loop/SKILL.md`: replace `git add -A` with a scoped add.
- Default `junk_patterns` set covering the classes seen in the wild (`.session-id*`, `*-kills.jsonl`,
  `*.log`, `.env*`).
- Config keys above + `skills/pr/SKILL.md` documentation of the new gate.
- Bats suite with fixtures for each bucket (missing artifact, undeclared ripple, junk sweep, clean),
  registered in CI; shellcheck-clean.

### Out of Scope
- Reviewing the *content* of the diff for bugs — `specclaw:code-reviewer` owns that. This change only
  judges **which files** are present.
- Auto-fixing: the auditor never unstages or reverts. It reports and blocks; a human or a follow-up
  task acts.
- A pre-commit hook or CI-side check independent of specclaw (possible follow-up; the `--strict` flag
  is designed to make it trivial later).
- Rewriting history on branches that already shipped a bad file set.
- Changing what the mandatory artifact set *is*.

## Impact

- **Files affected:** ~10 (estimated) — 1 new `bin/` script, 1 new agent definition, `specclaw-pr`,
  `specclaw-azdo-pr`, `specclaw-build`, `specclaw-loop`, `skills/pr/SKILL.md`, `skills/loop/SKILL.md`,
  `skills/build/SKILL.md`, `.specclaw/config.yaml` template, 1 new bats suite.
- **Complexity:** medium — the classifier is straightforward git plumbing; the care is in path
  normalisation (worktree strategy changes `cwd`, see `specclaw-build:283-291`) and in not
  false-positive-blocking legitimate work.
- **Risk:** medium — this gate can **block PRs that are actually fine**, which is worse than the
  current silent failure if it misfires. Mitigations: ship with `staged_files_block: false` for one
  release (same rollout the repo already chose for `code_review_block`), make `required-missing` and
  `suspicious` the only default BLOCK buckets, and keep `allowed_extra_paths` as the operator escape
  hatch. Removing PR creation from `build` is a workflow behaviour change and needs a release note.

## Open Questions

1. **Should `undeclared` ever block on its own**, or only ever WARN and defer to the auditor agent?
   Blocking is safer but will fire constantly on legitimate ripples.
2. **Is the auditor worth its token cost** when Layer 1 already catches the reported failures? Option:
   only spawn it when the undeclared count exceeds a threshold (e.g. >3 paths or >10% of the diff).
3. **`tasks.md` file lists are the source of truth for `declared`** — are they reliably accurate today?
   If tasks routinely under-declare, the undeclared bucket is noise and the design needs a different
   scope signal (e.g. `spec.md` affected-files).
4. **Removing PR creation from build** — does any existing automation (`/specclaw:auto`, `/specclaw:loop`,
   the mcd scheduler) depend on build opening the PR? Needs a check before committing to it.
5. Should the loop's scoped-add fallback **still `git add -A` when `tasks.md` is unparseable**, to avoid
   losing work in exactly the crash case escalation exists for?
6. Does the `suspicious` list belong in `config.yaml`, or should these paths simply be **added to
   `.gitignore`** in the offending repos — i.e. is specclaw fixing a symptom of missing ignore rules?

---

**To proceed:** Review this proposal and approve to begin planning.
