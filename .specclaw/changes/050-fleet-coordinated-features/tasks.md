# Tasks: specclaw-fleet coordinated multi-change features

**Change:** 050-fleet-coordinated-features
**Created:** 2026-11-08
**Total Tasks:** 6

## Tasks

### Wave 1: model

- [ ] `T1` — Feature graph: parse `Feature` and `Depends on` (proposal.md or change.md); waves; cycle and unknown-dependency errors; `item_dir` and the `features/` fallback in fleet and `specclaw-azdo-issue`; `feature plan` (AC-1)
  - Files: plugins/specclaw-fleet/lib/feature-graph.sh, plugins/specclaw-fleet/lib/feature.sh, plugins/specclaw-fleet/lib/naming.sh, plugins/specclaw-fleet/lib/workitem.sh, plugins/specclaw-fleet/lib/trigger.sh, plugins/specclaw-fleet/lib/status.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-sync/bin/specclaw-azdo-issue, plugins/specclaw-fleet/tests/cases/ac27_feature_graph.sh
  - Kind: impl
- [ ] `T2` — `SPECCLAW_PR_TARGET` in `specclaw-azdo-pr`; the pod exports it; the draft PR uses it (AC-5)
  - Files: plugins/specclaw-sync/bin/specclaw-azdo-pr, plugins/specclaw-sync/tests/run-azdo-pr-description-tests.sh, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/image/draft-pr.sh, plugins/specclaw-fleet/tests/cases/ac28_pr_target.sh
  - Kind: impl

### Wave 2: coordination

- [ ] `T3` — Member state from records, tags and the PR API, with the ancestor fallback (AC-3)
  - Files: plugins/specclaw-fleet/lib/feature-state.sh, plugins/specclaw-fleet/tests/cases/ac29_feature_state.sh
  - Kind: impl
  - Depends: T1
- [ ] `T4` — `feature init`, `start` and `advance` (ready dispatch, failed blocks only its dependents, one conflict retry, integration once) (AC-2, AC-4)
  - Files: plugins/specclaw-fleet/lib/feature.sh, plugins/specclaw-fleet/lib/feature-run.sh, plugins/specclaw-fleet/tests/cases/ac30_feature_advance.sh
  - Kind: impl
  - Depends: T1, T3
- [ ] `T5` — Pod: `FLEET_MERGE_REF` merge, `FLEET_MODE=integrate`, manifest env (AC-5)
  - Files: plugins/specclaw-fleet/image/integrate.sh, plugins/specclaw-fleet/image/workspace.sh, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/lib/manifest.sh, plugins/specclaw-fleet/tests/cases/ac31_integrate_pod.sh, plugins/specclaw-fleet/tests/lib/entry-env.sh
  - Kind: impl
  - Depends: T2

### Wave 3: delivery

- [ ] `T6` — Pipelines trigger on `feature/*` and run advance; `/specclaw-fleet:feature` skill; README; CI (AC-6)
  - Files: plugins/specclaw-fleet/pipelines/dispatch.yml, plugins/specclaw-fleet/pipelines/dispatch-hosted.yml, plugins/specclaw-fleet/skills/feature/SKILL.md, plugins/specclaw-fleet/README.md, plugins/specclaw-fleet/tests/cases/ac32_feature_delivery.sh
  - Kind: config
  - Depends: T4, T5

## Legend

- `[ ]` Pending · `[x]` Complete · `[!]` Failed
