# Verification Report: 043-headless-pr-and-build-fixes

**Verified:** 2026-10-13
**Verdict:** PASS. All 12 criteria are met. AC-11 was settled by CI on PR #95: run 38302504333, and run 38304362459 after T6 was added. All three jobs are green.

## Commands run (macOS, bash 5.3 unless noted)

| Command | Exit | Result |
|---|---|---|
| `bash plugins/specclaw/tests/run-headless-pr-tests.sh` | 0 | 51 passed, 0 failed |
| `/bin/bash plugins/specclaw/tests/run-headless-pr-tests.sh` (bash 3.2.57) | 0 | 51 passed, 0 failed |
| `GIT_CONFIG_GLOBAL=/dev/null bash plugins/specclaw/tests/run-headless-pr-tests.sh` (CI-like git config) | 0 | 51 passed, 0 failed |
| `bash plugins/specclaw/tests/shellcheck-gate.sh` | 0 | no new findings (all 23 known findings are in the baseline) |
| `bash plugins/specclaw/tests/run-change-lock-tests.sh` | 0 | 27 passed, 0 failed |
| `bash plugins/specclaw/tests/run-staged-files-tests.sh` | 0 | 55 passed, 0 failed |
| all 50 CI suites, run locally | — | Every suite that fails here also fails on `main`, with the same failure count per suite. They are macOS-only tooling differences (BSD `wc`/`sed`, no `timeout`), not regressions. |

The suite drives the real scripts:
- Each project is a real git repo with a local bare `origin`.
- `gh` is a stub that logs every call.
- Every run goes through `run_bounded`, which uses perl `setsid` and an alarm. There is no controlling terminal, and a hang shows up as exit 124.

## Acceptance Criteria

| AC | Status | Evidence |
|---|---|---|
| AC-1 | MET | `specclaw-build` finalize puts both merge branches behind `git.merge_on_finalize == true`. AC-1a–f check: exit 0; HEAD stays on `specclaw/001-x`; the branch still exists; the `main` sha is unchanged; the output has `"merged": false` and `"errors": []`. |
| AC-2 | MET | AC-2a–c: with `merge_on_finalize: true` the output is `"merged": true`, HEAD is on `main`, and the feature branch is deleted. |
| AC-3 | MET | `pr_require_change_branch` refuses on the base branch or a detached HEAD, before any staging, push or PR call, in both scripts. AC-3a–h check: rc 1; the message names `specclaw/001-x` and `git.merge_on_finalize`; the `gh` log is **entirely empty**; the detached case; and azdo on `main`. |
| AC-4 | MET | `pr_require_tty_or_die` checks `/dev/tty` and exits 2 naming `pr.test_policy` and `none \| unit \| e2e \| both`. A failed `read` in the loop also exits 2. AC-4a–g, under `setsid`: rc 2 (not 124) and the `config.yaml` checksum is unchanged, for both `specclaw-pr` and `specclaw-azdo-pr`. |
| AC-5 | MET | `pr_publish_branch` does a plain push only when the upstream has the branch's own name. Otherwise it runs `push -u <upstream remote \| origin \| only remote> HEAD`, and with no remote, or several remotes and no `origin`, it dies. Tests: <br>• **AC-5a–d:** a fresh branch is published, `gh pr create` is called, and the upstream is set. <br>• **AC-5e–g:** with no remote it exits 1 and never calls `gh`. <br>• **AC-5h–l:** a branch whose upstream is `origin/main` (as `specclaw-build` creates it), under `push.default=simple`, is published as itself. `main` on origin does not move, the upstream is moved to `origin/specclaw/001-x`, and a branch whose upstream has its own name gets a plain push. AC-5h, 5i, 5k and 5l **fail against the previous lib**. |
| AC-6 | MET | `pr_stage_change_trail` uses `:(exclude)<change>/.lock` for the add, the commit and the uncommitted check. The fixture's `.gitignore` lacks the lock rule, and after the run no commit in `main..HEAD` contains a `/.lock/` path. |
| AC-7 | MET | `specclaw-check-staged` puts `.specclaw/changes/*/.lock/*` under `suspicious`, ahead of the rule that treats the change folder as declared. AC-7 and AC-7b cover a lock in another change and a lock inside the change's own folder. |
| AC-8 | MET | AC-8a–e: the rule is added exactly once over two runs; a tracked lock produces the `git rm --cached` hint and stays tracked; ensure-init is silent once fixed; a read-only `.gitignore` is skipped silently. |
| AC-9 | MET | AC-9a–b: `state.json`, `status.md` and `STATUS.md` show no changes after the run, and the last commit is `record PR`. AC-5b also covers the push: it compares origin's branch head with local HEAD after the run, and that HEAD is the `record PR` commit. |
| AC-10 | MET | `build-engine.md`, `full/build.md`, `full/pr.md` and `templates/config.yaml` cover the default of no merge, the `merge_on_finalize` key, the no-terminal exit 2, the branch check, `push -u` and the bookkeeping commit. |
| AC-11 | MET | CI run 38302504333 on PR #95 is green in all three jobs: Parser regression suite (which includes the new headless PR / finalize step), ShellCheck bin scripts and Validate plugin manifests. The first run (38301715231) failed twice, and both are fixed. (1) Plugin versions were out of sync: `specclaw-pr`'s auto-bump rewrote only the first `"version"` in `marketplace.json`. (2) AC-3d: CI's bare origin had HEAD pointing at a missing `master`, so the base lookup fell back to `gh repo view`. The fixture now creates the bare repo with `-b main`. |
| AC-12 | MET | Added as T6 after PR #95 opened with every box empty. `tick_met_acs` in `specclaw-pr`, plus verdict parsing from the `**Verdict:**` line. AC-12a–b: on PASS, both boxes are ticked. AC-12c–e: a PARTIAL report that says "PASS" earlier in the text produces a body without `**Verdict:** PASS`, ticks the MET AC-1 and leaves the PENDING AC-2 open. Against the old first-word parse, AC-12e fails. |

NFR-1 is met: `lib/pr-git.sh` is sourced by both scripts, and the inline copies of the staging and push code are gone. NFR-4 is met: `gh` is a stub and every remote is a local bare repo.

## Edge cases

- **Worktree with merge off:** the same gate covers both strategies (code read).
- **Existing upstream:** a plain push happens only when the upstream has the branch's own name. Any other upstream is replaced via `push -u` (AC-5h–l).
- **ensure-init outside a git repo:** silent, and no `.gitignore` is created.
- **`test_policy` already set:** there is no terminal check, so configured projects behave as before.
- **Detached HEAD:** refused (AC-3e and AC-3f).

## Issues found during verify, now fixed

1. **Real bug: an upstream of another name broke the PR step.** `specclaw-build` cuts the branch from `origin/<base>`, so the branch's upstream starts as `origin/main`, and a plain `git push` from there is refused. The old `|| true` hid this, and the first version of the lib turned it into a hard failure before the PR existed. Fixed in `lib/pr-git.sh`, with AC-5h–l added.
2. **`specclaw-pr` could call `gh repo view` before refusing to run.** The base lookup now runs only when HEAD is not already the change branch, and AC-3d now requires the `gh` log to be empty.
3. **ensure-init printed "Permission denied" on a read-only `.gitignore`.** The redirect order is fixed, and AC-8e covers it.
4. **Test assertions were tightened:** AC-1f now checks for `"errors": []`, and AC-3d requires an empty `gh` log.

## Still open (notes from the code review, none blocking)

- `specclaw-azdo-pr`'s successful-PR path is not tested end to end, because that would need a fake Azure DevOps API. The logic it runs is in the shared lib, which the `specclaw-pr` tests exercise.
- `check_test_policy` is still copied in both PR scripts. Only the terminal check is shared.
- `specclaw-build` still has an empty `if … then :` branch where the condition could have been inverted.

**Code Review:** APPROVED_WITH_NOTES. The first pass found 7 issues: 1 BLOCK, 3 WARN and 3 NOTE. After the fixes, the BLOCK and all 3 WARNs are resolved. One WARN was downgraded to a NOTE, so 5 NOTEs remain open.

## Summary

**Passed:** 12/12
**Failed:** 0/12
**Verdict:** PASS
