# Verification Report: 053-fleet-optin-status-run

**Verified:** 2026-11-09
**Model:** claude-opus-5-5
**Verdict:** FAIL (review verdict not clean; the operator closed the loop after the last final pass)

## Acceptance Criteria

- **AC-1:** pass. `fleet:` config precedence, quoting and comments; local cluster settings come only from env or `.specclaw/.env`; secret-looking and non-numeric values are refused (an injection payload is never evaluated); trusted-branch security keys are enforced. Evidence: `ac22_settings.sh`.
- **AC-2:** pass. The templates keep only compile-time names plus `fleetTrustedBranch`; the dispatch step clears `FLEET_KUBE_CONTEXT` and fails closed without the trusted config and commit. Evidence: `ac15_delivery.sh`, `ac22_settings.sh`, `ac10_pipeline_script.sh`.
- **AC-3:** pass. `optin` assigns and tags only as the token identity, re-adds consent the assignee did not add, refuses someone else's item, writes nothing on a dry run, and makes no write when the history is unreadable. Evidence: `ac23_optin.sh`, `run-azdo-issue-optin-tests.sh`.
- **AC-4:** pass. `status` shows fields, `--since`, the consent rule, `?` for anything unreadable, and `did-not-run` judged on the queued run's `queueTime`. `--watch` always ends (terminal states or `--timeout`) and makes no writes. Evidence: `ac24_status.sh`.
- **AC-5:** pass. The run skill covers many changes (opt-in, parallel trigger, `--run` on the watch); the setup skill writes `fleet:` and keeps local settings in `.env`; CI is registered. Evidence: `ac26_skills.sh`.
- **AC-6:** pass. `doctor` reaches AzDO over REST with the PAT, names a missing scope, and treats an unparsable answer as skip; GHCR 401/403 wording; `cluster=` order; the delivery prompt; trigger names a missing change and uses the pushed `fleet:` settings. Evidence: `ac25_hosted_fixes.sh`, `ac16_doctor.sh`.

## Test Results

- `bash plugins/specclaw-fleet/tests/run-fleet-tests.sh`: 210 passed, 0 failed.
- `run-azdo-issue-{claim,history,fields,optin}-tests.sh`: all passed. `run-codex-plugin-tests.sh` and `run-plugin-split-tests.sh`: passed.
- ShellCheck at warning level: clean.
- **Live, from demo-studio, with settings from `fleet:` and `.specclaw/.env` only:**
  - `doctor`: every cluster, vault and image check is ok. The AzDO checks are skipped because the PAT lacks the Build and Service Connections read scopes, and the message now says so.
  - `status`: shows real work items, records and the Hetzner Job.
  - `optin --dry-run`: names the caller.

## Issues Found

`specclaw-review verdict`: "OPEN, 17 rounds; last round 0/1/3". The last round's major and minors are fixed in 9b7c627 but not re-reviewed. See `follow-ups.md`.

## Summary

**Passed:** 6/6 criteria.
**Verdict:** FAIL, capped by the review verdict. The operator chose to stop the loop after the last final pass.

Review: OPEN — 17 rounds, final pass missing, models sonnet/opus; last round 0/1/3 b/M/m
