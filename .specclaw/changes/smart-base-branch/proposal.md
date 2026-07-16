# Proposal: Smart Base Branch Detection

**Created:** 2026-07-16
**Status:** 🟡 Draft

## Problem

_What problem are we solving? Why does it matter?_

SpecClaw's git plumbing hardcodes assumptions about the base branch, producing wrong results on any repo whose default branch isn't `main` (or whose operator isn't sitting on it):

1. **Branching from wherever HEAD is.** `specclaw-build setup` creates change branches with plain `git checkout -b` — from the current HEAD. Run it while on another feature branch and the new change silently stacks on unrelated work. No fetch happens, so even on the right branch the base can be stale.
2. **Merge-target guessing.** `specclaw-build finalize` picks `main` if it exists, else `master`. Repos using `develop`, `trunk`, or release branches merge into the wrong place.
3. **PR base hardcoded.** `specclaw-pr` correctly detects the default branch via `origin/HEAD` for its version-bump check — then ignores that and runs `gh pr create --base main`. The detection exists; the PR call doesn't use it.

## Proposed Solution

_What are we building? High-level approach._

One `detect_base_branch()` helper (duplicated into both scripts per the repo's self-contained-script convention, like `yaml_val`), with a deterministic priority chain:

1. `git.base_branch` config value (explicit override — release-branch workflows)
2. `origin/HEAD` (`git rev-parse --abbrev-ref origin/HEAD`; self-heal with `git remote set-head origin --auto` when unset)
3. `gh repo view --json defaultBranchRef` when gh is available
4. `main` → `master` existence fallback (today's behavior, last resort)

Wired into three sites:
- **`specclaw-build setup`** — fetch the base, create new change branches from `origin/<base>` (local base fallback when offline); warn when the working HEAD differs from the base so stacking is deliberate, never accidental. Existing-branch resume behavior unchanged.
- **`specclaw-build finalize`** — merge into the detected base instead of the main/master guess.
- **`specclaw-pr`** — `gh pr create --base "<detected>"`; reuse the same helper for the version-bump comparison (one source of truth).

New config key `git.base_branch: ""` (empty = auto-detect), seeded in the template with comments.

## Scope

### In Scope
- `detect_base_branch()` in `specclaw-build` and `specclaw-pr`.
- Branch-creation-from-base + divergence warning in setup; base-targeted merge in finalize.
- `--base` fix in specclaw-pr.
- `git.base_branch` in templates/config.yaml.
- Test coverage with a local-remote git fixture (bare repo as origin, non-`main` default).
- README + CHANGELOG + version bump.

### Out of Scope
- Fork-workflow support (push remote selection, `--head owner:branch`) — separate follow-up change.
- Stacked-change branching (branch B off change A) — future work.
- worktree-per-change internals beyond the shared branch-creation path.

## Impact

- **Files affected:** ~7 (estimated)
- **Complexity:** medium
- **Risk:** low-medium — touches git plumbing, but default detection resolves to `main` on standard repos (today's behavior); fixture tests lock the chain

## Open Questions

1. Fetch failure handling (offline)? **Resolved:** fall back to local base ref with a warning; never block on network.
2. Should `direct` strategy also warn about base divergence? **Resolved:** no — direct mode explicitly means "work on the current branch"; leave untouched.

---

**To proceed:** Review this proposal and approve to begin planning.
