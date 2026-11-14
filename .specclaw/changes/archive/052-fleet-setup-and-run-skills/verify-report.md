# Verification Report: 052-fleet-setup-and-run-skills

**Verified:** 2026-11-08
**Model:** claude-opus-5-5
**Verdict:** FAIL (review verdict not clean; the operator chose to open the PR)

## Acceptance Criteria

- AC-1: pass. The Dockerfile has no claude download, and it has `DISABLE_UPDATES=1`, the baked key and a build-time fingerprint check (`ac13_claude_fetch.sh`).
- AC-2: pass. Verified fetch, `claude_fetch_s` recorded, then the agent runs (`ac13_claude_fetch.sh`).
- AC-3: pass. Each case records `claude-verify-failed`: bad signature, a different key, a wrong checksum, a missing platform, plus expired, revoked, rollback and size cases (`ac13_claude_fetch.sh`).
- AC-4: pass (`ac14_dispatch_inputs.sh`).
- AC-5: pass (`ac7_entrypoint.sh`).
- AC-6: pass. Both platforms build, `packages: write` only, and the overwrite guard holds (`ac15_delivery.sh`, `ac19_env_and_guard.sh`).
- AC-7: pass. The doctor runs read-only, and "could not ask" is reported as skip (`ac16_doctor.sh`, `ac20_context_resume.sh`).
- AC-8: pass. Trigger gates, retry, direct and queue all behave as specified, and the gate verdicts match dispatch's (`ac17_trigger.sh`, `ac18_gate_parity.sh`).
- AC-9: pass (`ac15_delivery.sh`, `ac10_pipeline_refs.sh`).
- AC-10: pass. Both skills exist, and `run-fleet-tests.sh` runs every case file in CI.

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh`: 174 passed, 0 failed (run twice).
- `bash plugins/specclaw/tests/run-codex-plugin-tests.sh`: all checks passed.
- `shellcheck -S warning` on the fleet lib, image, bin and tests: clean.

## Not verified live

These items have no live evidence yet. Each needs operator confirmation:
- GHCR publish, through a `fleet-v*` tag;
- the hosted pipeline on `bistec-dev-uat`;
- a measured `claude_fetch_s`.

## Issues Found

`specclaw-review verdict`: "OPEN — 12 rounds, final pass missing; last round 0/3/4 b/M/m". The three majors from final round 12 are fixed in 0c1675c, which has not been re-reviewed:
- the watchdog budget now counts setup time;
- resume matches the change's own branch exactly;
- `doctor` reports an unreachable context as skip.

After three final passes in a row that each found new majors, the operator chose to stop the loop and open the PR. The open minors are in `follow-ups.md`.

## Summary

**Passed:** 10/10 criteria (offline suite).
**Verdict:** FAIL, capped by the review verdict. The PR is opened at the operator's direction.

Review: OPEN — 12 rounds, final pass missing; last round 0/3/4 b/M/m
