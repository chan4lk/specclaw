# Tasks: Headless-safe build finalize and PR creation

**Change:** 043-headless-pr-and-build-fixes
**Created:** 2026-10-12
**Total Tasks:** 6

## Summary

Wave 1 contains three independent script fixes: finalize, ensure-init/check-staged, and the shared PR lib. Wave 2 wires the lib into both PR scripts. Wave 3 adds the documentation and the regression suite that proves AC-1 to AC-9 end to end.

## Tasks

### Wave 1 — Independent script fixes

- [x] `T1` — Gate finalize's merge on `git.merge_on_finalize` (AC-1, AC-2)
  - Files: plugins/specclaw/bin/specclaw-build, plugins/specclaw/templates/config.yaml
  - Estimate: small
  - Kind: impl
  - Notes: Read the key with `yaml_val` and treat anything other than `true` as false. Put both merge branches (worktree and branch) behind it. When false: keep `merged=false`, add no error, remove no worktree. Add the key under `git:` in the template with a one-line comment.

- [x] `T2` — Lock ignore backfill in ensure-init; `.lock/` counted as suspicious in check-staged (AC-7, AC-8)
  - Files: plugins/specclaw/bin/specclaw-ensure-init, plugins/specclaw/bin/specclaw-check-staged
  - Estimate: small
  - Kind: impl
  - Notes: Reuse init's exact block text and grep guard for `.specclaw/changes/**/.lock/`. Only act inside a git work tree. Warn on stderr (never untrack) when `git ls-files` finds tracked `*/.lock/*`. In check-staged, add `.specclaw/changes/*/.lock/*` to the suspicious patterns.

- [x] `T3` — Create `lib/pr-git.sh` with the shared PR git helpers (FR-2–FR-5, FR-8)
  - Files: plugins/specclaw/lib/pr-git.sh
  - Estimate: medium
  - Kind: impl
  - Notes: `pr_require_change_branch <expected> <base>`, `pr_require_tty_or_die`, `pr_stage_change_trail <change_path>` (pathspec `:(exclude)<change_path>/.lock`, used for both add and the porcelain check), `pr_publish_branch` (upstream → `git push`; else origin or the only remote → `git push -u`; else die listing the remotes), `pr_commit_bookkeeping <change> <url> <files…>` (warn-only). Callers supply `die`/`warn`. The lib defines no top-level side effects.

### Wave 2 — Wire both PR scripts

- [x] `T4` — Use `lib/pr-git.sh` in specclaw-pr and specclaw-azdo-pr (AC-3–AC-6, AC-9)
  - Files: plugins/specclaw/bin/specclaw-pr, plugins/specclaw-sync/bin/specclaw-azdo-pr
  - Depends: T3
  - Estimate: medium
  - Kind: impl
  - Notes: Source the lib (core: `$SCRIPT_DIR/../lib`; sync: core-lib resolution as in specclaw-bf-quality-collect). Call `pr_require_change_branch` first. Before the prompt loop, call `pr_require_tty_or_die` and treat a failed read as exit 2. Replace the inline add/porcelain-check/push. Call `pr_commit_bookkeeping` after `save_pr_url` (core) and after the ADO status write (sync).

### Wave 3 — Docs and regression suite

- [x] `T5` — Update docs; add `run-headless-pr-tests.sh` and register it in CI (AC-1–AC-11)
  - Files: plugins/specclaw/references/build-engine.md, plugins/specclaw/references/full/build.md, plugins/specclaw/references/full/pr.md, plugins/specclaw/tests/run-headless-pr-tests.sh, .github/workflows/ci.yml
  - Depends: T1, T2, T4
  - Estimate: medium
  - Kind: test
  - Notes: The suite uses temp repos, a local bare origin and a stub `gh` (no network). Cover AC-1 to AC-9 for core, plus AC-3 and AC-4 for `specclaw-azdo-pr` (its ADO API call is never reached on those paths). Run each script under a bounded wrapper (`timeout`, else a perl alarm) so a regression of FR-3 fails rather than hangs. Run the shellcheck gate.

- [x] `T6` — Tick the PR body's acceptance criteria from the verify verdict (AC-12)
  - Files: plugins/specclaw/bin/specclaw-pr, plugins/specclaw/tests/run-headless-pr-tests.sh, plugins/specclaw/references/full/pr.md
  - Depends: T4
  - Estimate: small
  - Kind: impl
  - Notes: Added after PR #95 opened with every acceptance criterion unticked. Read the verdict from the `**Verdict:**` line first. On PASS, tick every box; otherwise tick the criteria whose report row says MET.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
