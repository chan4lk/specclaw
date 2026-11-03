# Spec: Headless-safe build finalize and PR creation

**Change:** 043-headless-pr-and-build-fixes
**Created:** 2026-10-12
**Size:** bounded

## Overview

Five defects in `specclaw-build finalize`, `specclaw-pr` and `specclaw-azdo-pr` break the full flow, or quietly corrupt the branch, when no person is at a terminal (agent Bash, CI, `/specclaw:auto`). All five were found by a headless v0.8.0 full-flow run, and all exist unchanged in v0.7.9. The open questions in the proposal were approved with their proposed answers, and those answers are the requirements below.

## Requirements

### Functional Requirements

- **FR-1 — finalize does not merge by default.** A new config key, `git.merge_on_finalize`, defaults to `false`. When it is false or missing, `specclaw-build finalize` under `branch-per-change` or `worktree-per-change` runs the configured checks and records the build. It leaves the current branch, the feature branch and any worktree untouched, and reports `"merged": false` without adding a merge-related entry to `errors`. When the key is `true`, today's merge path runs unchanged.
- **FR-2 — the PR step refuses to run on the base branch.** `specclaw-pr` and `specclaw-azdo-pr` exit non-zero, before any staging, push or PR call, when the current branch is the base branch or HEAD is detached. The message names the expected branch `<branch_prefix><change>` and says it may have been merged by `finalize` with `git.merge_on_finalize: true`.
- **FR-3 — the test-policy prompt never runs without a terminal.** When `pr.test_policy` is empty and `/dev/tty` cannot be opened for reading, both PR scripts exit 2 with a message naming `pr.test_policy` and its four values, and change nothing. A `read` that fails inside the prompt loop also exits 2, so the loop cannot spin.
- **FR-4 — publish the branch before creating the PR.** Both PR scripts push before creating the PR:
  - With an upstream already set, they run a plain `git push`.
  - Without one, they run `git push -u <remote> HEAD`. `<remote>` is `origin` when it exists, otherwise the only remote. With no remotes, or several remotes and none of them `origin`, the script fails and lists the remotes.
  - A failed push exits non-zero before the PR is created, naming the remote and branch.
- **FR-5 — the lock is never staged and never blocks.** Both PR scripts stage the change folder with `<change_path>/.lock` excluded, and exclude it from the "planning trail uncommitted" check that follows. An untracked or ignored `.lock/meta.json` therefore neither gets committed nor fails that check.
- **FR-6 — the staged-files check flags lock files.** `specclaw-check-staged` puts any `.specclaw/changes/*/.lock/` path on the branch in `suspicious`.
- **FR-7 — existing projects get the lock ignore rule.** When `.specclaw/` already exists, `specclaw-ensure-init` appends the `.specclaw/changes/**/.lock/` block from `specclaw-init` to the project's `.gitignore` if the rule is missing, creating the file if needed. It also prints one stderr warning if git already tracks lock files, naming the `git rm --cached` command to run. It never removes or untracks anything, and stays silent once nothing is left to fix.
- **FR-8 — the PR bookkeeping gets committed.** After `save_pr_url`, `specclaw-pr` commits whatever its bookkeeping changed among the change's `state.json`, the change's `status.md` and `.specclaw/STATUS.md`, using the message `specclaw(<change>): record PR <url>`, and then pushes. Both steps only warn on failure and never change the exit status, because the PR already exists.

- **FR-9 — the PR body shows what verify found.** It is added after PR #95 opened with every box empty. `specclaw-pr` reads the verdict from the report's `**Verdict:**` line, and falls back to the first PASS/FAIL/PARTIAL word only when that line is missing. In the PR body's copy of the spec's acceptance criteria:
  - **PASS** ticks every box.
  - **Any other verdict** ticks only the criteria whose `verify-report.md` table row has MET (or PASS/✅) in its status cell.
  - `spec.md` itself is never edited.

### Non-Functional Requirements

- **NFR-1:** The shared PR git logic lives in one sourced file, `plugins/specclaw/lib/pr-git.sh`. `specclaw-azdo-pr` sources it the same way `specclaw-bf-quality-collect` sources `lib/quality-scan.sh`. This removes the duplicate copies that let both scripts carry the same three bugs.
- **NFR-2:** No new shellcheck findings (`tests/shellcheck-gate.sh`).
- **NFR-3:** Every new test suite is registered in `.github/workflows/ci.yml`.
- **NFR-4:** The tests make no network calls. `gh` is a stub, and remotes are local bare repos.

## Acceptance Criteria

- [ ] **AC-1:** `finalize` with `branch-per-change` and no `merge_on_finalize` key leaves HEAD on the feature branch, keeps the branch, leaves `main` unchanged, and reports `"merged":false` with no merge entry in `errors`. (FR-1)
- [ ] **AC-2:** `finalize` with `merge_on_finalize: true` still merges into `main` and deletes the feature branch, as it does today. (FR-1)
- [ ] **AC-3:** `specclaw-pr` run on `main` exits non-zero, names `specclaw/<change>`, and never calls `gh`. (FR-2)
- [ ] **AC-4:** `specclaw-pr` run with `test_policy: ""` and no controlling terminal (`setsid`/`</dev/null`, wrapped in a 20 s timeout) exits 2 within the timeout, names `pr.test_policy`, and leaves `config.yaml` unchanged. `specclaw-azdo-pr` behaves the same. (FR-3)
- [ ] **AC-5:** On a branch with no upstream and a local bare `origin`, `specclaw-pr` pushes the branch so it exists on `origin`, then calls the `gh` stub. With no remote at all it exits non-zero before calling `gh`. (FR-4)
- [ ] **AC-6:** With an untracked, un-ignored `changes/<change>/.lock/meta.json`, `specclaw-pr` succeeds, and the lock file is in no commit on the branch. (FR-5)
- [ ] **AC-7:** `specclaw-check-staged` reports a committed `.specclaw/changes/x/.lock/meta.json` under `suspicious`. (FR-6)
- [ ] **AC-8:** On a project whose `.gitignore` lacks the lock rule, `specclaw-ensure-init` adds it exactly once over two runs. A tracked lock file produces the warning, and the file is still tracked afterwards. (FR-7)
- [ ] **AC-9:** After a successful `specclaw-pr`, `git status --porcelain` shows no changes to the change's `state.json` or `status.md`, or to `.specclaw/STATUS.md`. The last commit message contains `record PR`. (FR-8)
- [ ] **AC-10:** `references/build-engine.md`, `references/full/build.md`, `references/full/pr.md` and `templates/config.yaml` describe the new behaviour: no default merge, the `merge_on_finalize` key, and a no-terminal run failing with an instruction to set `pr.test_policy`.
- [ ] **AC-11:** All existing suites stay green in CI. The new suite or suites are registered there, and the shellcheck gate is clean. (NFR-2, NFR-3)
- [ ] **AC-12:** With verdict PASS, every acceptance-criteria box in the PR body is ticked. With a PARTIAL report that says "PASS" earlier in the text and has rows `AC-1 | MET` and `AC-2 | PENDING CI`, the body says `**Verdict:** PARTIAL`, ticks AC-1 and leaves AC-2 open. (FR-9)

## Edge Cases

- `worktree-per-change` with `merge_on_finalize: false` keeps the worktree. Removing it was part of the merge path.
- A branch that already has an upstream on a remote other than `origin` gets a plain `git push`, which honours that upstream.
- `ensure-init` runs outside a git repo, or where `.gitignore` is not writable: the backfill is skipped silently. The same `|| true` pattern `specclaw-init` uses applies.
- `test_policy` already set means no prompt and no TTY check, so CI behaviour does not change for configured projects.
- A detached HEAD (some CI checkouts) is treated as "not on the change branch" under FR-2.

## Approach

| File | Change |
|---|---|
| `plugins/specclaw/lib/pr-git.sh` (new) | **The one design decision:** both PR scripts share these git steps instead of keeping copies. `pr_require_change_branch`, `pr_require_tty_or_die`, `pr_stage_change_trail`, `pr_publish_branch`, `pr_commit_bookkeeping` |
| `plugins/specclaw/bin/specclaw-pr` | source the lib; use the helpers in place of the inline add, push and prompt; commit the bookkeeping after `save_pr_url` |
| `plugins/specclaw-sync/bin/specclaw-azdo-pr` | source the lib through the core-lib path; use the same helpers |
| `plugins/specclaw/bin/specclaw-build` | gate both merge branches on `git.merge_on_finalize` |
| `plugins/specclaw/bin/specclaw-ensure-init`, `specclaw-check-staged` | lock-rule backfill and tracked-lock warning; `.lock/` counted as suspicious |
| `plugins/specclaw/templates/config.yaml`, `references/build-engine.md`, `references/full/build.md`, `references/full/pr.md` | docs |
| `plugins/specclaw/tests/run-headless-pr-tests.sh` (new), `.github/workflows/ci.yml`, `tests/shellcheck-baseline.txt` (never grows) | tests |

## Dependencies

- None external. The tests use `git`, local bare repos and a stub `gh`.

## Notes

- **Assumption:** the `--json` output of `specclaw-check-staged` keeps its four buckets, so `.lock/` joins the existing `SUSPICIOUS` patterns.
- **Assumption:** `pr_require_tty_or_die` checks with `{ : </dev/tty; } 2>/dev/null`. `[ -t 0 ]` alone is wrong here, because the prompt reads `/dev/tty`, not stdin.
- The CHANGELOG/release note for the `merge_on_finalize` default flip goes in the PR body.
