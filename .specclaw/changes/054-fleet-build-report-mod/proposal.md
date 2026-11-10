# Proposal: specclaw-fleet build report and mod

**Created:** 2026-11-09
**Status:** ✅ Approved

## Problem

After the demo-studio build (six changes, three waves, about 2h 29m), the only way to see how the fleet run went was to piece it together by hand from four places:
- Kubernetes Job and pod status;
- the work-item records;
- Azure DevOps pipeline runs and PRs;
- the review rounds on each branch.

That data does not last. Pods are cleaned up after a while (001's Job is already gone). The pod log keeps only the last 4,000 bytes, so cost and turn counts were lost. Nothing ties a pipeline run to the change it dispatched.

The operator wants to see a fleet build visually whenever they need, the way `doctor` shows setup.

## Proposed Solution

1. **Record what a report needs, on the work item, when it happens.** Today's run records gain:
   - **dispatch:** `pipeline_run=` (from `BUILD_BUILDID`), `wave=` for feature runs;
   - **pod:** `agent_started=` and `agent_ended=`, `agent_s=`, and the cost and model counters taken from the agent's full JSON output (`total_cost_usd`, `num_turns`, model), read from `agent.log` before it is cut down for display;
   - **delivery:** `review_rounds=`, `agent_commits=`, the PR number.

   Records are the durable source. The cluster and AzDO only fill gaps.
2. **`specclaw-fleet report [<change>...|--feature <module>] [--since ISO] [--json] [--html <file>] [--save]`.** Read-only, like `doctor`.
   - **Inputs:** the records first, then the PR API (opened and merged times), then pipeline runs (queue, start and finish times), then the cluster, when it is reachable, for runs still going.
   - **Output:** a short table and totals:
     - wall clock;
     - Jobs;
     - agent minutes;
     - hosted pipeline minutes;
     - review rounds and commits;
     - Claude download time;
     - cost, when it was recorded.
   - **`--json`:** the rows and totals.
   - **`--html <file>`:** one self-contained page, with no network, holding the timeline (pipeline, agent run, PR open until merged, by wave), the lifecycle table and the totals. It is the same view as today's dashboard.
   - **`--save`:** writes `.specclaw/fleet/report.json` (gitignored) for the mod.
3. **A specclaw-fleet mod** (Claude Code only, built the way the specclaw mod is: `hooks/mod.json` → `register.tsx`, pure logic in `hooks/core/` with bun tests). It reads `.specclaw/fleet/report.json` and never calls the network itself.
   - **`/fleet-pane`:** a pane beside the chat with the timeline and the lifecycle table for the latest build (or one feature), plus how old the snapshot is.
   - **Band:** `fleet · 2 running · 4 PRs open · last run 13:51`, hidden when there is no report.
   - **Status line:** `fleet: 2 running`.
   - **Refresh:** after any `specclaw-fleet trigger`, `status` or `report` tool call, and from a pane button that shows the command to run (`specclaw-fleet report --save`).
4. **`/specclaw-fleet:report` skill:** runs the report for the asked scope, saves it, opens the pane or writes the HTML file, and summarises in a few lines.

## Scope

### In Scope
- The new record fields in the entrypoint and dispatch, with tests.
- The `report` command, its HTML template and its tests (offline, with stubbed AzDO and kubectl).
- The mod: pane, band, status line, refresh, its bun tests, and `claude plugin validate`.
- The skill and README sections, and the gitignore entry for `.specclaw/fleet/`.

### Out of Scope
- Publishing the report anywhere (an Artifact or a dashboard) from the CLI. The skill may offer that in chat.
- Live streaming of pod logs into the pane.
- Codex hosts (mods are Claude Code only); there, `report --html` is the view.
- Backfilling runs from before this change beyond what records, PRs and pipeline runs still hold. The six demo-studio runs can be reconstructed because their PRs and runs still exist.

## Impact

- **Size:** architectural. It adds a new report interface and a new mod, and changes the record format that other tools read.
- **Files affected:** about 14.
- **Complexity:** medium.
- **Risk:** low. The report and the mod only read. The new record fields are added; none change.

## Open Questions

Resolved 2026-11-09 (operator approved the defaults):
- The mod reads only the saved snapshot (`.specclaw/fleet/report.json`); it never runs commands or calls the network.
- The pane shows the latest build (or the feature asked for); history is a follow-up.
- Cost is shown, labelled "API-equivalent estimate", because setup-token runs are not billed per token.
