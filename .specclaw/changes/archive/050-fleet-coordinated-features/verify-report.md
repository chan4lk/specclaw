# Verification Report: 050-fleet-coordinated-features

**Verified:** 2026-11-09
**Model:** claude-opus-5-5
**Verdict:** FAIL (review verdict not clean; the operator stopped the loop after the second final pass)

## Acceptance Criteria

- **AC-1:** pass. Membership and dependencies come from `proposal.md` or a lean `change.md`; waves are topological; an unknown or foreign dependency, a cycle, a bad name and an empty feature are refused with names. Evidence: `ac27_feature_graph.sh`.
- **AC-2:** pass. `feature init` writes the record and the work item, and refuses an empty feature or a name that collides with a change. Evidence: `ac30_feature_advance.sh`.
- **AC-3:** pass. Member state follows the PR-only model: merged only through a completed PR; then failed, running, conflict/pr_open, stalled and consent; anything unreadable is `?`. Evidence: `ac29_feature_state.sh` (table).
- **AC-4:** pass. `advance` dispatches only ready members; a failed member blocks only its dependents; a conflict gets one retry, tagged after it launches, then is marked failed; `stalled` and `?` count as errors; integration is dispatched exactly once. Evidence: `ac30_feature_advance.sh`.
- **AC-5:** pass. `SPECCLAW_PR_TARGET`; children's PRs go into the feature branch; the integrate pod (feature approval, `specclaw/integrate-<m>`, a real or draft PR, publishing an existing draft); the merge ref, with real conflicts only. Evidence: `ac28_pr_target.sh`, `ac31_integrate_pod.sh`.
- **AC-6:** pass. Pipelines trigger on `feature/*` and run `advance`; `feature start` creates the branch only when it is missing and stops on an `ls-remote` error; the skill exists; CI is registered. Evidence: `ac32_feature_delivery.sh`, `ac30_feature_advance.sh`.

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh`: 228 passed, 0 failed.
- `run-azdo-issue-{claim,history,fields,optin}-tests.sh`, `run-azdo-pr-description-tests.sh` (28 passed), `run-codex-plugin-tests.sh`, `run-plugin-split-tests.sh`: all passed.
- ShellCheck at warning level: clean.
- No live feature run yet. See `follow-ups.md`.

## Issues Found

`specclaw-review verdict`: "ESCALATE — 6 rounds; last round 0/3/1". All of them are fixed in c0eb330 but not re-reviewed.

## Summary

**Passed:** 6/6 criteria (offline).
**Verdict:** FAIL, capped by the review verdict. The operator chose to stop the loop.

Review: ESCALATE — 6 rounds, final pass missing, models sonnet/opus; last round 0/3/1 b/M/m
