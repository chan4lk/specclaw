# Verification Report: 051-fleet-azdo-agents

**Verified:** 2026-11-09
**Model:** claude-opus-5-5
**Verdict:** FAIL (review verdict not clean; the operator stopped the loop for a deadline)

## Acceptance Criteria

- **AC-1:** pass. Both templates run a single job, `dispatch`, with `timeoutInMinutes: 10` (`ac33_hosted_minutes.sh`).
- **AC-2:** pass. The checkout is sparse to `.specclaw`, depth 1, with persisted credentials, and the trusted config is still read (`ac33`).
- **AC-3:** pass. The specclaw fetch is blob-less and sparse to the two fleet plugins and still verifies the SHA. Checked live against GitHub: about 1 MB (`ac33`).
- **AC-4:** pass. The README has the "Hosted minutes" section (`ac33`).

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh`: 234 passed, 0 failed. ShellCheck is clean.
- Review rounds 1–3 fixed issues in code carried over from 050:
  - no PR is created when the PR search cannot be read;
  - the integration PR is marked ready only on a fresh `pass` marker;
  - pipelines ignore `.specclaw/.env`;
  - the pod resolves a single PR target.

## Issues Found

`specclaw-review verdict`: escalated in round 4; its fixes are made but not re-reviewed. See `follow-ups.md`.

## Summary

**Passed:** 4/4 criteria.
**Verdict:** FAIL, capped by the review verdict. The operator stopped the loop.
