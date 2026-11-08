# Tasks: specclaw-fleet opt-in, status, many-change run, fleet: config

**Change:** 053-fleet-optin-status-run
**Created:** 2026-11-08
**Total Tasks:** 6

## Tasks

### Wave 1: config and AzDO primitives

- [x] `T1` — `fleet:` config loader wired into the router; pipelines drop per-setting variables and clear the kube context (AC-1, AC-2)
  - Files: plugins/specclaw-fleet/lib/settings.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/pipelines/dispatch.yml, plugins/specclaw-fleet/pipelines/dispatch-hosted.yml, plugins/specclaw-fleet/tests/cases/ac22_settings.sh, plugins/specclaw-fleet/tests/cases/ac10_pipeline_refs.sh, plugins/specclaw-fleet/tests/lib/pipeline-env.sh
  - Kind: impl
- [ ] `T2` — `specclaw-azdo-issue whoami | optin | records` (AC-3, AC-4)
  - Files: plugins/specclaw-sync/bin/specclaw-azdo-issue, plugins/specclaw-sync/tests/run-azdo-issue-optin-tests.sh, .github/workflows/ci.yml
  - Kind: impl

### Wave 2: commands

- [ ] `T3` — `specclaw-fleet optin` (AC-3)
  - Files: plugins/specclaw-fleet/lib/optin.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/cases/ac23_optin.sh
  - Kind: impl
  - Depends: T1, T2
- [ ] `T4` — `specclaw-fleet status` with `--json`, `--watch` and `--since` (AC-4)
  - Files: plugins/specclaw-fleet/lib/status.sh, plugins/specclaw-fleet/lib/status-render.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/cases/ac24_status.sh
  - Kind: impl
  - Depends: T1, T2
- [ ] `T5` — Hosted-run fixes: doctor AzDO over PAT REST, GHCR 401/403 wording, `cluster=` order, delivery in the prompt, trigger missing-change message (AC-6)
  - Files: plugins/specclaw-fleet/lib/doctor-azure.sh, plugins/specclaw-fleet/lib/launch.sh, plugins/specclaw-fleet/lib/trigger.sh, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/tests/cases/ac25_hosted_fixes.sh, plugins/specclaw-fleet/tests/cases/ac16_doctor.sh
  - Kind: impl
  - Depends: T1

### Wave 3: skills and docs

- [ ] `T6` — run skill for many changes, setup skill writes `fleet:`, dispatch skill settings, README (AC-5)
  - Files: plugins/specclaw-fleet/skills/run/SKILL.md, plugins/specclaw-fleet/skills/setup/SKILL.md, plugins/specclaw-fleet/skills/dispatch/SKILL.md, plugins/specclaw-fleet/README.md
  - Kind: docs
  - Depends: T3, T4, T5

## Legend

- `[ ]` Pending · `[x]` Complete · `[!]` Failed
