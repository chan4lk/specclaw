# Proposal: specclaw-fleet one-command opt-in, trigger and watch; settings in config

**Created:** 2026-11-08
**Status:** ✅ Approved

## Problem

The operator created proposals 002–007 in demo-studio, along with work items #209–#214, and pushed to main. The pipeline ran twice, but nothing reached the cluster. Every item had no assignee and no `fleet:auto` tag, so dispatch skipped each change as "not opted in", and nothing outside the pipeline log said why. There is no single view of where each change stands: the work item, its tags and assignee, the last fleet record, and the Job or pod on the cluster. Today, finding out takes `az boards`, the AzDO log API and `kubectl` against an isolated kubeconfig. The operator's words: "this is hard".

## Proposed Solution

Two new subcommands and a wider `run` skill.

1. **`specclaw-fleet optin <change>...`**: self-consent in one step. For each change, it reads the work item. If the item is unassigned or already assigned to the caller, it assigns the item to the caller and adds `fleet:auto`, so the tag's revision is made by the caller. It **refuses** an item assigned to someone else and names that person: only they can opt in. The caller is the identity behind `AZDO_TOKEN`, read from AzDO's `connectionData`, not from `az account`. That way, the revision's `revisedBy` (which the consent gate checks) is the same identity the command assigned. The command is idempotent, and `--dry-run` prints the plan.
2. **`specclaw-fleet status [<change>...]`**: read-only, one line per change. It shows the work-item id, state, assignee, fleet tags, and the last fleet record from its comments (dispatched, running, pr_open or failed, plus `exit`, `pr` and `draft`). It also shows the live Job and pod phase on the cluster (`FLEET_KUBE_CONTEXT`). With no arguments, it lists every change whose proposal is approved. With `--json`, it prints machine output. With `--watch`, it repeats every N seconds until every listed change is terminal.
3. **`/specclaw-fleet:run` takes one or many changes** and does the whole flow:
   - **Plan:** list the changes and show `status`.
   - **Opt-in:** one confirmation covers the opt-in and names the caller. It never assigns to anyone else.
   - **Trigger:** every listed change is triggered in parallel, which the operator chose on 2026-11-08. Before triggering, the skill warns that each run spends the caller's plan, and that changes touching the same area may produce conflicting PRs. `--sequential` waits for each change to finish before starting the next.
   - **Watch:** `status --watch` until each change ends in a PR (or draft PR) or a recorded failure.
   - **Report:** each outcome.
4. **Settings live in `.specclaw/config.yaml`.** Today every run needs a long env prefix: `FLEET_VAULT=kv-scfleet-965892 FLEET_KUBE_CONTEXT=bistec-dev-uat …`. A new `fleet:` block holds the non-secret settings: `vault`, `kube_context`, `kubeconfig`, `namespace`, `image`, `claude_version`, `default_agent`, `deadline_minutes`, `pipeline`, `kube_connection`, `azure_connection`, `remote` and `ref`.
   - Every subcommand (`dispatch`, `trigger`, `doctor`, `optin`, `status`) and the pipeline's dispatch step resolve each setting in this order: flag, then env, then `fleet:` config, then built-in default.
   - Secrets never go in config. The PAT stays in the gitignored `.specclaw/.env`, and credentials stay in Key Vault. A test refuses a config whose `fleet:` block holds a token-like value.
   - **This reverses 049's "never read from config.yaml".** The pipeline YAML that sets these values already lives in the same repo, under the same branch policy, so config adds no new trust. The pipeline template keeps only what AzDO must know at compile time: the two connection names and the pinned specclaw SHA.
   - `/specclaw-fleet:setup` writes the block as it goes, so after setup every command runs with no env prefix.
5. **Fixes from the 2026-11-08 hosted run:**
   - `doctor` checks AzDO with `AZDO_TOKEN` over REST, not `az devops`. The vault and AzDO identities can differ (bg1467 vs chandima), and both groups of checks then run.
   - When GHCR refuses the token with 401 or 403, `doctor` says "package missing or private", not "network?".
   - The run record's `cluster=` is the `fleet.kube_context` name (or `FLEET_CLUSTER_NAME`), not whatever context the kubeconfig happens to name (`fleet`).
   - The agent prompt says the pod pushes the change branch and opens the PR after the agent exits, so the agent's summary stops saying "nothing pushed".
6. **`trigger` names a missing change.** For `trigger <change>` where the change dir does not exist on the pushed ref, it says "no change <change> on <remote>/<ref>" instead of "not approved".

## Scope

### In Scope
- `lib/optin.sh`, `lib/status.sh`, and router entries in `bin/specclaw-fleet`.
- `specclaw-azdo-issue` gains `whoami` (connectionData) and `assign`. Assign is rev-guarded, like the existing tag core.
- The `run` skill rewrite, README section, and tests (one per AC, table-driven).
- `trigger`'s missing-change message.
- `lib/settings.sh`: the one resolver for flag, env, config and default, used by every subcommand. The pipeline templates read it too.
- The four hosted-run fixes in item 5.

### Out of Scope
- Coordinated multi-change runs and the shared feature branch. That is change 050, which ships in the same 0.9.0 release.
- Assigning or tagging on anyone else's behalf: never.
- Secrets in `config.yaml`: never.

## Release

053, 050 and 051 ship together as **0.9.0**:
- every `plugin.json` and marketplace entry moves to 0.9.0 (a minor bump, not a patch);
- the image is tagged `fleet-v0.9.0`;
- demo-studio's pipeline moves to 0.9.0 and its `fleet:` block is filled in.

## Impact

- **Size:** bounded. It extends the existing `specclaw-fleet` CLI and its `run` skill. There is no new subsystem, and dispatch's gates are unchanged.
- **Files affected:** about 16.
- **Complexity:** medium.
- **Risk:** medium. `optin` writes to work items. It must never weaken the consent rule: a tag added by the caller only counts when the caller is the assignee, and the dispatch gate still checks that independently.

## Open Questions

- Resolved 2026-11-08: changes run in parallel by default, and `--sequential` is optional. `status` also shows the pipeline run before a Job exists.
