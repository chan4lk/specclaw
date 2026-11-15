# Code Review Report: 043-headless-pr-and-build-fixes

**Reviewed:** 2026-10-13
**Model:** Sonnet 5.5
**Verdict:** APPROVED_WITH_NOTES

## Summary

7 findings as first reviewed: 1 BLOCK, 3 WARN, 3 NOTE (see Re-review: 0 BLOCK, 0 WARN open)

Suite run: `run-headless-pr-tests.sh` 40/40 under bash 5.3 and under /bin/bash 3.2.57. Shellcheck gate clean. design.md absent (bounded change), D8 skipped.

## Findings

### [BLOCK] plugins/specclaw/lib/pr-git.sh:57-60 — Correctness
**Problem:** `if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' ...; then git push >&2 || die ...` treats any upstream as pushable with a plain `git push`. Under the default `push.default=simple`, that push is refused when the upstream's branch name differs from the local name. specclaw's own `specclaw-build` creates the change branch from the remote-tracking ref (`bin/specclaw-build:278: git checkout -b "$branch_name" "$start_point"`, `bin/specclaw-build:261: git branch "$branch_name" "$start_point"`, with `start_point="origin/$base_branch"` at line 231). Git sets the upstream of such a branch to `origin/<base>`. I reproduced it: a branch made with `git checkout -b feat --track origin/main` gets "fatal: The upstream branch of your current branch does not match the name of your current branch". The old code hid this with `git push 2>/dev/null || true`. Now it dies before the PR is created, on the normal specclaw path whenever `origin` exists. The suite never covers it: AC-5 only runs a branch with no upstream.
**Fix:** In the upstream branch, push to the same-named branch when the upstream's short name differs from the local name. For example, compare `${upstream#*/}` with `$branch` and fall through to the `git push -u <remote> HEAD` path on mismatch (taking `<remote>` from `branch.<name>.remote`). Add a test that creates the branch from `origin/main`.

### [WARN] plugins/specclaw/bin/specclaw-pr:719-723 — Correctness / spec compliance (FR-2, AC-3)
**Problem:** `pr_require_change_branch "...${CHANGE_NAME}" "$(detect_base_branch)"` runs `detect_base_branch`, which can call `git remote set-head origin --auto` (network) and `gh repo view` (`bin/specclaw-pr:137-143`) before the refusal. The spec says to refuse before any PR call and AC-3 says "never calls gh". With no `origin/HEAD` and no `git.base_branch`, a run on `main` still reaches `gh repo view`. The test hides this: `assert_not_contains "AC-3d gh pr create was never called" "pr create" ...` only greps for `pr create`, and the AC-3 fixtures leave `base_branch` empty.
**Fix:** Tighten AC-3d to assert the whole gh log is empty (and fix any resulting failure). Resolve the base without gh/network for the check, for example by comparing against `git.base_branch`, then local `main`/`master`.

### [WARN] plugins/specclaw/tests/run-headless-pr-tests.sh — Test quality
**Problem:** Several assertions are weaker than the ACs they claim.
- AC-9 (`:AC-9a/9b`) never checks that the bookkeeping commit was pushed. The push is half of FR-8 and the `pr_commit_bookkeeping` failure branches (warn-only, exit status unchanged) are untested.
- The `specclaw-azdo-pr` push, lock and bookkeeping paths have no test at all. Only its refusal and no-TTY exits are covered, although NFR-1 says the lib exists to keep the two scripts in step.
- AC-1f greps `'"errors"' -A3` for "merge". It is a fragile slice of the JSON, not a check that `errors` is empty.
- AC-4 and AC-3 azdo runs set `git.base_branch` so the API is never reached. The `get_default_branch` fallback path is untested, although it is one of the recorded deviations.
**Fix:** Assert `git --git-dir=$P.origin.git log -1 --format=%s refs/heads/specclaw/$CH` contains "record PR". Parse `errors` as JSON for AC-1f. Add an azdo case with a stubbed `adoapi_get` or curl.

### [WARN] plugins/specclaw/lib/pr-git.sh:87 — Correctness (post-PR safety)
**Problem:** `git push >/dev/null 2>&1 || warn ...` in `pr_commit_bookkeeping` has the same plain-push problem as the BLOCK above. For a branch whose upstream is `origin/<base>`, the bookkeeping commit is made locally but never pushed. It warns, so it does not abort, but the PR then lacks the commit and the local branch is ahead of it. Confirmed by the same reasoning: nothing in the function can abort the script (all calls are in `if !` or `||` contexts, `warn` is defined in both callers, and the `[[ ... ]] && files+=()` loop is safe under `set -e`). So the "never aborts" requirement holds.
**Fix:** Reuse the fix for `pr_publish_branch` (extract a `_push_current` helper).

### [NOTE] plugins/specclaw/bin/specclaw-pr:223-257 and plugins/specclaw-sync/bin/specclaw-azdo-pr:162-190 — YAGNI / duplication
**Problem:** Both copies of `check_test_policy` still carry an identical prompt loop with the same `read ... || exit 2` guard. NFR-1 exists to remove that kind of duplicate copy, but only the TTY probe was shared.
**Suggestion:** Optional follow-up: move the prompt loop into `pr-git.sh` as `pr_prompt_test_policy`.

### [NOTE] plugins/specclaw/bin/specclaw-build:446-449 — One-liner / simplicity
**Problem:** `if [[ "$merge_on_finalize" != "true" ]]; then :` followed by `elif ... worktree` and `elif ... branch-per-change` is an empty first arm used only to short-circuit the chain.
**Suggestion:** Wrap the two merge arms under `if [[ "$merge_on_finalize" == "true" ]]; then`, or inline it as `elif [[ "$merge_on_finalize" == "true" && "$git_strategy" == worktree-per-change ]]`. This is cosmetic, but it removes the no-op arm.

### [NOTE] plugins/specclaw/bin/specclaw-ensure-init:23-35 — Behaviour
**Problem:** The backfill edits the tracked `.gitignore` on every first run after upgrade, leaving the working tree dirty on whatever branch is current. The tracked-lock warning repeats on every invocation until the operator untracks. Both match FR-7 as written. Mentioned so the `.gitignore` edit is not a surprise in PR diffs.
**Suggestion:** None required.

## Judgement on the recorded deviations

- **Prompt text moved to stderr in `check_test_policy`:** correct, and a real fix. In `policy="$(check_test_policy)"`, the old prompt lines went into the captured value. Keep it.
- **`specclaw-azdo-pr` honours `git.base_branch`, falls back to `main`:** acceptable. It saves an API call, and `get_default_branch` already fell back to `main`. The only cost is the untested fallback (see WARN 3).

## Points checked and found sound

- **`git commit --only -- <dir> ":(exclude)<dir>/.lock"`:** works. A lock that is untracked or ignored is neither staged nor committed (AC-6 passes), and the same pathspec feeds the "still uncommitted" check.
- **`exit 2` inside `policy="$(check_test_policy)"` under `set -euo pipefail`:** the subshell's status 2 fails the assignment, so the parent exits 2. The parent's EXIT trap releases the lock, because traps do not run in the command-substitution subshell. AC-4 confirms exit code 2 for both scripts.
- **bash 3.2:** `local -a files=()` is guarded by `${#files[@]} -gt 0` before expansion, and `"${spec[@]}"` is never empty. No empty-array expansion under `set -u` occurs. The suite is green under /bin/bash 3.2.57.
- **Scope:** changed files match the `## Approach` map. `.specclaw/STATUS.md` is bookkeeping.

## Verdict Rationale

The structure is sound. The lock exclusion, exit-status propagation, bash 3.2 behaviour and warn-only bookkeeping all check out, and the suite and shellcheck gate pass. One correctness defect blocks approval. `pr_publish_branch` uses a plain `git push` whenever any upstream exists, but the branches specclaw itself creates track `origin/<base>`, so `push.default=simple` rejects the push. The PR step then aborts on the main specclaw path, which is worse than the old silent `|| true`. The tests do not cover that case. Fix the push, and tighten the AC-3 and AC-9 assertions, before merge.

## Re-review

Re-checked against the uncommitted working-tree diff. Suite: 46 passed under /bin/bash 3.2.57 (coordinator reports the same under 5.3 and a clean shellcheck gate).

- **BLOCK pr-git.sh `pr_publish_branch` — RESOLVED.** A plain `git push` is now used only when `branch.<b>.remote` is set, is not `.`, and `branch.<b>.merge == refs/heads/<b>`. Any other upstream (including `origin/main` from `specclaw-build`) goes to `git push -u <upstream remote> HEAD`, so the branch is published as itself and the base is never pushed to. New AC-5h..5l cover this under `push.default=simple`, including that origin's `main` does not move. Once published the upstream is the own-name branch, so the later `git push` in `pr_commit_bookkeeping` is a valid plain push.
- **WARN specclaw-pr base lookup before refusal (AC-3) — RESOLVED.** `detect_base_branch` is skipped when HEAD is already the expected change branch, and AC-3d now asserts the gh log is empty. Residual NOTE: on the base branch or a detached HEAD the lookup still runs (it is needed to name the base) and may call `gh repo view` when `git.base_branch` and `origin/HEAD` are unset. The refusal still happens before any staging, push or PR call, so this is acceptable.
- **WARN test quality — RESOLVED for specclaw-pr.** AC-1f now asserts `"errors": []`. AC-5b compares origin's branch head with local HEAD (the `record PR` commit), which proves the bookkeeping push. AC-5h..5l fail against the old lib and pass now (per the coordinator).
- **WARN bookkeeping push (plain `git push` in `pr_commit_bookkeeping`) — RESOLVED** by the publish fix plus the AC-5b strengthening.
- **azdo success-path test — OPEN, downgraded to NOTE.** The azdo push, lock and bookkeeping wiring is not exercised end to end because it needs an ADO API stub. The logic is in the shared lib, which specclaw-pr's tests cover, and azdo's calls mirror specclaw-pr's one-liners, so this no longer warrants a WARN. Add the stub as a follow-up.
- **ensure-init read-only `.gitignore` — RESOLVED.** `} 2>/dev/null >> "$GITIGNORE" || true` silences the failed redirect; AC-8e covers it.
- **Original NOTEs 1-3 — still open**, all optional: duplicated `check_test_policy` prompt loop, the no-op `if ... then :` arm in `specclaw-build`, and the `.gitignore` edit / repeating tracked-lock warning in `ensure-init`.

**New verdict: APPROVED_WITH_NOTES.** No BLOCK or WARN findings remain open.
