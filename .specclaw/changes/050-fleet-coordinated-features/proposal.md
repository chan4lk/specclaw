# Proposal: specclaw-fleet — coordinated multi-proposal feature delivery

**Created:** 2026-11-07
**Status:** ✅ Approved

## Problem

A feature or module is usually several specclaw changes, and some depend on others. Change 049 dispatches one change at a time, and each PR targets `main`. Nothing groups the changes, orders them by dependency, or ships them together once all are done.

`specclaw-azdo-pr` also reads its PR target only from `git.base_branch` in config (`plugins/specclaw-sync/bin/specclaw-azdo-pr:580`). A fleet job therefore cannot open a PR into a feature branch without editing committed config.

## Proposed Solution

Extend `specclaw-fleet` (049):

1. **Feature = Azure Boards Feature work item + integration branch `feature/<module>`.** Each member change is a child work item. A child's dependencies come from the work item's `Predecessor` links.
2. **`specclaw-fleet feature start <feature-id>`.**
   - Creates `feature/<module>` from `main` when it is missing.
   - Groups the children into waves using the predecessor links. A cycle is refused.
   - Dispatches wave 1 through `specclaw-fleet dispatch … --ref feature/<module>`. Each child can name its own `--agent` (claude or codex) and target cluster (kube context). Runs use the child assignee's credentials and respect 049's per-user Codex serialization.
3. **PRs target the feature branch.** Add a per-run override to `specclaw-azdo-pr`, `SPECCLAW_PR_TARGET` or `--target <branch>`. It wins over `git.base_branch`, so fleet jobs open `specclaw/<NNN> → feature/<module>`.
4. **Fan-in, event-driven.** A Boards service hook fires when a child moves to `Done` (its PR merged). It triggers `specclaw-fleet feature advance`, which:
   - dispatches the next wave once all of its predecessors are Done;
   - when every child is Done, runs the integration verify on `feature/<module>` and opens `feature/<module> → main`, linked to the Feature work item.
5. **Merge conflicts.** If a child PR can't merge into the feature branch, `advance` dispatches one fix job on that child's branch, rebased onto the feature branch. A second failure marks the child `Failed` for a human.

## Scope

### In Scope
- `bin/specclaw-fleet feature start|advance|status`, plus skill and tests: wave grouping, cycle refusal, the all-Done gate, conflict retry.
- The `SPECCLAW_PR_TARGET` / `--target` override in `plugins/specclaw-sync/bin/specclaw-azdo-pr`, with a regression test.
- AzDO pipeline template for `advance`, started by a service hook or incoming webhook. No polling job.

### Out of Scope
- Any change to the core `plugins/specclaw/`.
- Automatically splitting a feature into proposals. A human still proposes and approves each child.
- Auto-merging PRs. A human still merges each child PR and the final PR to `main`, under branch policies.
- AzDO agent hosting (051).

## Impact

- **Size:** architectural. It adds the feature orchestration interface on top of 049.
- **Files affected:** ~8 (estimated)
- **Complexity:** medium
- **Risk:** medium. Wave ordering and conflict retries are where coordination bugs will show up.

## Open Questions

- Should dependencies come from Boards `Predecessor` links, or from a `depends_on:` list in each change's `proposal.md`? A `depends_on:` list keeps them in git, but the two can drift apart.
- Integration verify: run it in a fleet job (Claude or Codex) on the feature branch, or in an AzDO build on a self-hosted agent (051)?
- Should a `Failed` child block the whole feature, or let the remaining waves continue?

## Dependency Bypass

- Depends on **049-fleet-runner-dispatch** (`dispatch`, work-item fields). Build only after 049 is merged. This is not a bypass; it is listed so `plan` orders the work.
