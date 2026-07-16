# Spec: Smart Base Branch Detection

**Change:** smart-base-branch
**Created:** 2026-07-16
**Status:** 🟡 Draft

## Overview

Replace SpecClaw's hardcoded base-branch assumptions (branch from HEAD, merge into main-or-master, PR to main) with one deterministic detection chain, configurable by `git.base_branch`, defaulting to behavior identical to today's on standard `main`-based repos.

## Requirements

### Functional Requirements

- **FR1 — Detection chain.** `detect_base_branch()` resolves, in order: (1) non-empty `git.base_branch` config; (2) `origin/HEAD` via `git rev-parse --abbrev-ref origin/HEAD`, attempting `git remote set-head origin --auto` once when unset; (3) `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` when gh exists; (4) local `main` if it exists, else `master`, else `main`. Echoes the bare branch name.
- **FR2 — Branch from base.** `specclaw-build setup` (branch-per-change and worktree-per-change): when creating a NEW change branch, fetch the base (`git fetch origin <base>`, non-fatal on failure) and create from `origin/<base>` when that ref exists, else from local `<base>`, else from HEAD with a warning. Resume of an existing branch is unchanged.
- **FR3 — Divergence warning.** When setup creates a new branch while the current HEAD is neither the base branch nor its tip, emit a warning naming both, so stacking is a visible choice.
- **FR4 — Merge to base.** `specclaw-build finalize` merges the change branch into the detected base (checkout base first), replacing the main/master guess.
- **FR5 — PR base.** `specclaw-pr` passes `--base "<detected base>"` to `gh pr create`, and its version-bump comparison uses the same helper (single source of truth).
- **FR6 — Config key.** `git.base_branch: ""` added to templates/config.yaml with comments; empty string = auto-detect. Absent key behaves as empty.
- **FR7 — Docs.** README configuration example + short explanation; CHANGELOG entry; version bump 0.5.3 in both version files.

### Non-Functional Requirements

- **NFR1 — Backward compatible.** On a repo whose default branch is `main` with origin/HEAD set, all three sites behave exactly as before (same branch names, same merge target, same PR base).
- **NFR2 — Offline safe.** No step blocks or fails on network absence; fetch failures warn and fall back to local refs.
- **NFR3 — Portability.** Plain bash + coreutils + git; gh optional; jq not required (use `gh -q`).

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- [ ] **AC1** — Fixture repo with a bare origin whose default branch is `develop` (origin/HEAD → develop): `detect_base_branch` echoes `develop` from both scripts' code paths.
- [ ] **AC2** — Same fixture with `git.base_branch: "release/1.0"` in config: detection echoes `release/1.0` (override beats origin/HEAD).
- [ ] **AC3** — Fixture with no origin remote: detection falls back to local `main`/`master` without error.
- [ ] **AC4** — `specclaw-build setup` on the fixture, run from a side branch, creates the change branch from `origin/develop` tip (commit equality asserted) and prints the divergence warning.
- [ ] **AC5** — Existing-branch resume path unchanged: second setup run switches to the branch with the resume warning, no re-creation.
- [ ] **AC6** — `specclaw-pr`'s `gh pr create` invocation contains `--base "$BASE_BRANCH"` (no hardcoded main); version-bump check uses the same variable.
- [ ] **AC7** — `templates/config.yaml` contains commented `base_branch` under `git:`.
- [ ] **AC8** — Full test suite passes including new fixture cases; `bash -n` clean on both scripts.
- [ ] **AC9** — README + CHANGELOG updated; version 0.5.3 in both version files, in sync.

## Edge Cases

- origin exists but origin/HEAD unset (fresh clone of bare repo) → `set-head --auto` attempted once; failure falls through to gh/main-master.
- Detached HEAD during setup → divergence warning fires (HEAD name reported as detached).
- Base branch name containing slashes (`release/1.0`) → quoted everywhere; branch-prefix composition unaffected (change branches keep `specclaw/` prefix).
- gh installed but unauthenticated → `gh repo view` fails silently, chain falls through.

## Dependencies

- None new. Touches `specclaw-build`, `specclaw-pr`, templates/config.yaml, tests.

## Notes

Fork-workflow PR support explicitly deferred (proposal Out of Scope).
