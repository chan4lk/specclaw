# Proposal: only integration branches write the committed STATUS.md

**Created:** 2026-11-10
**Status:** 🟢 Approved (operator, 2026-11-10: "go with the integration branch option")

## Problem

`.specclaw/STATUS.md` is derived output. `specclaw-update-status` rebuilds it from every change's `state.json` and `tasks.md`, plus live `gh`/`az` PR lookups. It is committed, and every lifecycle step on every change branch rewrites it. So any two branches that both advance a change conflict on it when the second one merges.

- demo-studio `catalog-admin`: after PR 1393 (008) merged, PR 1394 (012) showed `conflicts`, and `.specclaw/STATUS.md` was its only conflicting file. The fleet's conflict retry re-dispatched 012, a full agent run spent on a generated file. Every parallel fleet wave hits this.
- A merge driver cannot fix it. AzDO and GitHub merge PRs on the server, where `.gitattributes` merge drivers don't run.
- The operator still wants the committed file: it is how a branch's overall status is read in the AzDO/GitHub web UI.

## Proposed Solution

1. **Branch-aware output in `specclaw-update-status`.** It writes `.specclaw/STATUS.md` only on an integration branch: `git.base_branch` from config, `main`, `master`, or `feature/*`. It also writes there when passed `--integration`, or outside a git work tree (unchanged behaviour). On any other branch, and on a detached HEAD, it writes the same dashboard to `$(git rev-parse --git-path specclaw-STATUS.md)`, inside `.git`, which is never tracked and needs no `.gitignore` entry. It still prints `OK: Updated <path>`. So change branches, and the fleet pods working on them, never modify the committed file, and the conflict cannot happen.
2. **Readers use the path it prints.** The `status` skill, `references/full/status.md` and the `auto` skill run `specclaw-update-status` first, then read the file named in its `OK: Updated <path>` line. `/specclaw:status` stays accurate on every branch.
3. **The fleet pipeline refreshes the committed copy.** `pipelines/dispatch-hosted.yml` gains a final step that runs on `main` and `feature/*` (the branches it already triggers on, whenever a `state.json` changes, i.e. after each merge):
   - `specclaw-update-status --integration .specclaw`
   - if the file changed, commit it as `specclaw: refresh STATUS.md [skip ci]` and push to the run's branch with the job token (`persistCredentials`)
   - a rejected push (branch policy, or the branch moved) is a warning, not a failure; the next run refreshes it
   The step fetches `plugins/specclaw` alongside the fleet plugins in the pinned-ref sparse checkout. The setup skill notes the permission it needs: the build service needs **Contribute** on the repo, and protected branches stay unrefreshed with a warning.

## Scope

### In Scope
- `plugins/specclaw/bin/specclaw-update-status` (branch rule, `--integration`)
- `plugins/specclaw/skills/status/SKILL.md`, `references/full/status.md`, `plugins/specclaw-extras/skills/auto/SKILL.md`
- `plugins/specclaw-fleet/pipelines/dispatch-hosted.yml`, `skills/setup/SKILL.md` (permission note), README line
- Tests: table-driven over branch kinds (base, main, master, feature/x, change branch, detached, no git, `--integration` on a change branch). Each asserts where the file was written and that the tracked file is untouched on a change branch. A pipeline-template test checks the refresh step and `[skip ci]`.
- Version bump.
- Rollout: re-pin demo-studio's pipeline file to the merge SHA.

### Out of Scope
- The content and format of STATUS.md.
- The self-hosted `pipelines/dispatch.yml`: same change later, if it is used.
- Per-change `status.md` and `state.json`. Each is written only by its own change's branch, so it doesn't conflict.

## Impact

- **Size:** bounded
- **Files affected:** about 8, plus tests
- **Risk:** low. On a change branch the committed STATUS.md shows the branch it was cut from until the next merge refresh, and `/specclaw:status` shows that checkout's live view.
- **One-time cost:** branches already in flight (demo-studio 009, 010, 011) have modified STATUS.md, and each conflicts once on merge. Resolve by taking the target's copy, and the next refresh rewrites it.
