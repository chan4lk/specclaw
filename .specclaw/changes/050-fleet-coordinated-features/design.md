# Design: specclaw-fleet coordinated multi-change features

**Change:** 050-fleet-coordinated-features
**Created:** 2026-11-08

## Technical Approach

A feature is a **work-item-backed item like a change**. It lives at `.specclaw/features/<module>/`, holding `proposal.md`, `status.md` and `state.json`. Everything already built for changes then applies to it unchanged:
- the work item;
- `optin`, the assignee and `fleet:auto` consent;
- the per-user credential;
- dispatch's gates;
- `status`.

Two lookups learn about the `features/` directory:
- **fleet:** a new `item_dir <name>` helper resolves `changes/<name>`, falling back to `features/<name>`. `work_item_id`, `proposal_approved`, `trigger_pushed_tree` and `status` use it.
- **`specclaw-azdo-issue`:** `CHANGE_DIR` falls back to `features/<name>` in the same way.

Coordination has no state store. `feature advance` derives each member's state on every run, from four sources:
- git (the member lines);
- Boards (tags and the run records);
- the AzDO PR API (whether the PR completed, and its `mergeStatus`);
- the change branch, as an ancestor fallback.

`advance` is therefore idempotent and safe to run on every push to `feature/<module>`. The pipeline runs it there: a child PR merging into the feature branch is exactly the event that should advance the feature. That needs no service hook and no polling.

## Components

| File | Role |
|---|---|
| `lib/feature-graph.sh` | parse `Feature` and `Depends on` from `proposal.md` or `change.md`; members; waves (Kahn's algorithm); cycle and unknown-dependency errors; pure |
| `lib/feature-state.sh` | member state from records, tags and the PR API (`azdo_rest git/pullrequests/<id>`); the ancestor fallback |
| `lib/feature.sh` | `feature init / plan / start / advance` router and actions |
| `lib/naming.sh` (+`item_dir`), `lib/workitem.sh`, `lib/trigger.sh`, `lib/status.sh` | `features/` fallback |
| `plugins/specclaw-sync/bin/specclaw-azdo-issue` | `CHANGE_DIR` falls back to `features/<name>` |
| `plugins/specclaw-sync/bin/specclaw-azdo-pr` | `SPECCLAW_PR_TARGET` override |
| `image/entrypoint.sh`, `image/workspace.sh`, `image/integrate.sh` | `SPECCLAW_PR_TARGET`, the `FLEET_MERGE_REF` merge, `FLEET_MODE=integrate` (approval path, branch, prompt, PR target) |
| `lib/manifest.sh` | passes `FLEET_MODE`, `FLEET_MERGE_REF` and `FLEET_PR_TARGET` to the agent container |
| `pipelines/*.yml` | `feature/*` trigger; run advance on feature branches |
| `skills/feature/SKILL.md`, `README.md` | operator flow |

## Key Decisions

- **Git is the source of truth for the graph.** That was the operator's choice. Boards links are written for visibility only.
- **Merged means the PR completed**, not git ancestry, because AzDO squash merges break ancestry. Ancestry is only a fallback for merges made by hand.
- **The feature is an item, not a special case.** Consent, credential, claim and records all reuse the change machinery. The integration run is dispatched like any item, in `integrate` mode.
- **`advance` runs in the pipeline on `feature/*`**, so the merge event drives progress, with no hook to install and no polling.
- **One automatic conflict retry**, after which a human takes over. The operator's rule that a failed child blocks only its dependents applies.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Two pipeline runs on the same feature race to dispatch the same member | dispatch's atomic `fleet:dispatched` claim already serialises it: the loser exits 3 |
| Integration dispatched twice | it is guarded by the feature item's own claim |
| The member list drifts from the record | the live scan wins, and `plan` warns about the drift |
| `feature/*` runs cost hosted minutes | `advance` takes seconds; the path filter still applies |
