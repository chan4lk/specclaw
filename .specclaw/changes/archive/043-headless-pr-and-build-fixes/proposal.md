# Proposal: Headless-safe build finalize and PR creation

**Created:** 2026-10-12
**Status:** ✅ Approved

## Problem

A full-flow run of v0.8.0 in a scratch project, driven headlessly (`claude -p`, one session per phase), completed propose → plan → build → verify. The scripted steps underneath it have five defects. Each exists unchanged in v0.7.9, so none is a 0.8 regression. Three of them break, or silently corrupt, the lifecycle whenever no person is at a terminal. That covers Claude's Bash tool, CI, and `/specclaw:auto`.

1. **`specclaw-build finalize` merges and deletes the change branch.** Under `git.strategy: branch-per-change` (the default), finalize checks out the base branch, runs `git merge --no-ff`, and deletes the feature branch (`bin/specclaw-build:465-494`). The build procedure ends at "**Branch:** specclaw/<change> → pushed (not merged)". `verify` and `pr` both need the branch, and the PR is supposed to be how the change reaches `main`. In the test the agent only avoided the merge by temporarily switching `git.strategy` to `direct` and restoring it afterwards. `references/build-engine.md` documents this merge, so it was intended once. It predates the PR phase and now contradicts it. `worktree-per-change` has the same merge path.
2. **`specclaw-pr` loops forever without a TTY.** On the first PR in a project where `pr.test_policy` is empty, it prompts in a `while true` loop with `read -r policy </dev/tty` (`bin/specclaw-pr:231-243`). With no controlling terminal the read fails every time and leaves `policy` empty, so the loop never ends and keeps a CPU core busy. Every v0.7.9-initialized project starts with `test_policy: ""`.
3. **`specclaw-pr` never publishes a new branch.** `git push 2>/dev/null || true` (`bin/specclaw-pr:794`) fails silently on a branch with no upstream. A real `gh pr create` then runs headless against an unpublished head and fails. 042 only worked because its branch had already been pushed by hand.
4. **Dispatch-lock files get committed in existing projects.** `.specclaw/changes/**/.lock/` is gitignored only by `specclaw-init` (since 3e543ce), so projects initialized earlier never get the rule. `specclaw-pr` itself runs `git add "$change_path"` on the change directory (`bin/specclaw-pr:766`) while the `pr` dispatch lock is held, so it commits `.lock/meta.json`. This happened on 041, on 042, and again in the scratch test.
5. **`specclaw-pr` leaves its own bookkeeping uncommitted.** After the PR is created, `save_pr_url` → `specclaw-set-phase` rewrites `state.json` and `status.md`, and nothing commits them. Every PR so far has needed a manual follow-up commit, such as `a9d0dfe` (041) and `ae597b1` (042).

## Proposed Solution

Five small, independent fixes to existing scripts:

1. **Make finalize's merge opt-in.** Add `git.merge_on_finalize` (default `false`). When it is false, finalize under `branch-per-change` / `worktree-per-change` runs the checks, records the build, leaves the branch checked out, and reports `"merged": false` with no error. Setting it to `true` restores today's behaviour for anyone who relied on a local merge without PRs. Update `references/build-engine.md` and the full `build.md` step text to match.
2. **Never prompt without a terminal.** Before the prompt, check for a usable TTY (`[ -t 0 ]` or a successful open of `/dev/tty`). Without one, exit 2 with a message naming the fix: `set pr.test_policy in .specclaw/config.yaml (none|unit|e2e|both)`. Also exit 2 if a `read` fails inside the loop, so the loop can never spin. The pr skill text tells the agent to ask the user and write the key when it sees that exit.
3. **Publish the branch before creating the PR.** If the current branch has no upstream, run `git push -u <remote> HEAD`, otherwise `git push`. The remote is `origin` unless config names another. A push failure becomes a hard error naming the remote and branch, raised before `gh pr create`, rather than being swallowed.
4. **Keep locks out of the commit and the repo, for every project.**
   - `specclaw-pr` stages the change directory with the lock excluded: `git add -- "$change_path" ':!*/.lock/*'`, or the equivalent pathspec.
   - `specclaw-check-staged` classifies `.specclaw/changes/*/.lock/**` as `suspicious`.
   - `specclaw-ensure-init` (which every phase already runs) appends the `.lock/` gitignore rule idempotently when it's missing, so pre-0.8 projects pick it up on their next run without re-initializing.
5. **Commit the post-PR bookkeeping.** After `save_pr_url`, commit `state.json`, `status.md` and `.specclaw/STATUS.md` (`specclaw(<change>): record PR <url>`) and push. Both steps are warn-only, because the PR already exists.

## Scope

### In Scope
- `plugins/specclaw/bin/specclaw-build`: the `merge_on_finalize` gate.
- `plugins/specclaw/bin/specclaw-pr`: the TTY guard, upstream push, lock-excluding add, and post-PR commit.
- `plugins/specclaw/bin/specclaw-ensure-init`: the idempotent `.lock/` gitignore backfill.
- `plugins/specclaw/bin/specclaw-check-staged`: `.lock/` as suspicious.
- `plugins/specclaw/templates/config.yaml`: the `git.merge_on_finalize: false` key, documented.
- `plugins/specclaw/references/build-engine.md`, `references/full/build.md`, and the pr skill/reference text for the new behaviour.
- Regression tests for each of the five items, registered in CI, including a no-TTY `specclaw-pr` run that must exit promptly.
- The `pr-azdo` path (`specclaw-azdo-pr`, in specclaw-sync), but only where it shares the same push or lock code. Each spot is confirmed during plan.

### Out of Scope
- The lean flow's build and pr steps, unless they call the same code paths, in which case they get the fixes for free.
- Changing `git.strategy` defaults, or removing the merge path entirely.
- Re-numbering or cleaning lock files already committed in old changes' history.
- Any `timeline.jsonl` ignore policy for this repo.

## Impact

- **Size:** bounded (each item alters an existing flow in an existing script; no new subsystem, and only one new config key)
- **Files affected:** ~10 (estimated)
- **Complexity:** medium
- **Risk:** medium. Item 1 changes default behaviour for anyone who relied on finalize merging locally. The opt-in key and a changelog note cover them.

## Open Questions

- **Item 1:** should `merge_on_finalize: true` still be allowed together with `/specclaw:pr`, or should `pr` refuse a change whose branch was already merged? Proposed: `pr` warns and stops when the branch no longer exists.
- **Item 2:** is exit 2 with a message enough, or should a non-interactive run default to `none` and print a warning? Proposed: fail. A silent default would enforce a test policy nobody chose.
- **Item 3:** which remote should a fresh branch go to when `origin` is missing and there are several remotes? Proposed: fail and name the remotes rather than guess. This matches the CLAUDE.md rule about naming `--repo`.
- **Item 4:** should `ensure-init` also report existing tracked lock files (`git ls-files '*/.lock/*'`) so the user can `git rm --cached` them? Proposed: warn once, never remove automatically.

---

**To proceed:** Review this proposal and approve to begin planning.
