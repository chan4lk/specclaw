# Tasks: fleet pods work for any Azure DevOps project, and can run a Postgres sidecar

**Change:** 058-fleet-any-project-postgres
**Total Tasks:** 4

## Wave 1

- [x] `T1` — Entrypoint exports AZDO_ORG/AZDO_PROJECT from a dev.azure.com clone URL; table test (AC-1)
  - Files: plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/tests/lib/entry-env.sh, plugins/specclaw-fleet/tests/cases/ac7_entrypoint.sh
  - Kind: impl
- [ ] `T2` — postgres_* fleet settings: parse, validate, trusted-branch image; table test (AC-2)
  - Files: plugins/specclaw-fleet/lib/settings.sh, plugins/specclaw-fleet/lib/podspec.sh, plugins/specclaw-fleet/tests/cases/ac22_settings.sh
  - Kind: impl

## Wave 2

- [ ] `T3` — Render the native Postgres sidecar, agent PG env and volumes; golden no-op test (AC-3)
  - Files: plugins/specclaw-fleet/lib/podspec.sh, plugins/specclaw-fleet/lib/manifest.sh, plugins/specclaw-fleet/tests/cases/ac32_postgres_sidecar.sh
  - Depends: T2
  - Kind: impl
- [ ] `T4` — Docs, doctor hint and version bump (AC-4)
  - Files: plugins/specclaw-fleet/README.md, plugins/specclaw-fleet/skills/setup/SKILL.md, plugins/specclaw-fleet/lib/doctor.sh, plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json
  - Depends: T1, T3
  - Kind: docs
