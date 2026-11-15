# Verification Report: 049-fleet-runner-dispatch

**Verified:** 2026-11-08
**Model:** claude-opus-5-5
**Verdict:** FAIL (review verdict not clean; the operator chose to open the PR)

## Acceptance Criteria

- AC-1: pass. `run-codex-plugin-tests.sh` passes, and both marketplaces list `specclaw-fleet` at 0.8.8 (`ac10_manifests.sh`).
- AC-2: pass (`ac2_onboard.sh`).
- AC-3: pass (`ac3_login.sh`).
- AC-4: pass (`ac4_gates.sh`).
- AC-5: pass (`ac5_launch.sh`, `ac12_claim.sh`).
- AC-6: pass (`ac6_codex_serial.sh`).
- AC-7: pass (`ac7_entrypoint.sh`, `ac7_egress_gate.sh`, `ac7_draft_pr.sh`).
- AC-8: pass (`ac8_writeback.sh`).
- AC-9: pass (`ac11_config.sh`).
- AC-10: pass (`ac10_manifests.sh`, `ac10_pipeline_script.sh`).
- AC-11: pass. The suites are registered in `ci.yml`, and ShellCheck is clean at warning level.

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh`: 113 passed, 0 failed.
- `bash plugins/specclaw/tests/run-codex-plugin-tests.sh`: all checks passed.
- `shellcheck -S warning` on the fleet lib, image and bin: clean.

## Live end-to-end (2026-11-07)

The live run used demo-studio on Azure DevOps, a self-hosted agent and Rancher Desktop K3s. The full chain worked:
1. the pipeline;
2. dispatch, the work-item claim and the per-run Secret;
3. the Job, with the egress gate passing;
4. the clone and the headless agent, including the review loop;
5. a push to the change branch and a draft PR (demo-studio work item #208, PR #1375).

## Issues Found

`specclaw-review verdict`: "ESCALATE — 14 rounds, final pass missing; last round 0/5/6 b/M/m". After review round 14, the operator stopped the loop. Later fixes on this branch, and the 052 branch stacked on it, address several of those findings. They were not re-reviewed as 049.

## Summary

**Passed:** 11/11 criteria (offline suite).
**Verdict:** FAIL, capped by the review verdict. The PR is opened at the operator's direction.

Review: ESCALATE — 14 rounds, final pass missing; last round 0/5/6 b/M/m
