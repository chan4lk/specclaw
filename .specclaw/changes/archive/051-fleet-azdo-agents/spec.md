# Spec: specclaw-fleet minute-lean Microsoft-hosted pipelines

**Change:** 051-fleet-azdo-agents
**Created:** 2026-11-09
**Size:** bounded

## Functional Requirements

- **FR-1 Bounded job.** Both templates run their steps in one job, `dispatch`, with `timeoutInMinutes: 10`. The pool stays at the root (hosted: `vmImage: ubuntu-latest`).
- **FR-2 Sparse checkout.** `checkout: self` keeps `fetchDepth: 1` and `persistCredentials: true`, and adds `sparseCheckoutDirectories: .specclaw`. The trusted-branch fetch reads only `.specclaw/config.yaml` and keeps working.
- **FR-3 Lean specclaw fetch (hosted template).** The pinned-SHA fetch uses `--filter=blob:none` and a sparse checkout of `plugins/specclaw-fleet` and `plugins/specclaw-sync`. The SHA check stays.
- **FR-4 Docs.** The README section "Hosted minutes" covers:
  - the free grant (1 parallel job, 1,800 min/month, private projects);
  - typical minutes per dispatch run;
  - where to see usage (Organization settings → Parallel jobs);
  - that the agent work runs on the cluster, not on hosted minutes;
  - when to buy a hosted parallel job, or to enable the deferred overflow agent.

## Non-Functional Requirements

- NFR-1: the two templates' dispatch scripts stay identical; ShellCheck is clean.
- NFR-2: tests are offline and parse the YAML.

## Acceptance Criteria

- **AC-1:** both templates have exactly one job named `dispatch`, with `timeoutInMinutes: 10`, holding all the steps (FR-1).
- **AC-2:** checkout is sparse to `.specclaw` with depth 1 and persisted credentials, and the dispatch step still reads the trusted config (FR-2).
- **AC-3:** the hosted fetch is blob-less and sparse to the two plugin directories, and still verifies the SHA (FR-3).
- **AC-4:** the README has the "Hosted minutes" section (FR-4).

## Approach

Change the YAML only; no script logic moves. The step script is identical in both templates, and the existing pipeline tests extract it, so those tests keep running unchanged.

File map:
- `plugins/specclaw-fleet/pipelines/dispatch.yml`, `dispatch-hosted.yml`
- `plugins/specclaw-fleet/README.md`
- `plugins/specclaw-fleet/tests/cases/ac33_hosted_minutes.sh` (new), plus `tests/lib/pipeline-env.sh` and `ac15_delivery.sh` if the extraction paths change
