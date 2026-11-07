# Tasks: specclaw-fleet setup and run skills

**Change:** 052-fleet-setup-and-run-skills
**Created:** 2026-11-07
**Total Tasks:** 6

## Tasks

### Wave 1 — runtime claude and dispatch inputs

- [x] `T1` — Public image: no baked claude; fetch, verify and time at pod start; per-run budget wording (AC-1, AC-2, AC-3, AC-5)
  - Files: plugins/specclaw-fleet/image/Dockerfile, plugins/specclaw-fleet/image/claude-release.asc, plugins/specclaw-fleet/image/claude-fetch.sh, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/image/bin/claude, plugins/specclaw-fleet/tests/lib/gpg-env.sh, plugins/specclaw-fleet/tests/cases/ac13_claude_fetch.sh
  - Kind: impl
- [x] `T2` — Dispatch inputs: FLEET_CLAUDE_VERSION, FLEET_IMAGE_PULL_SECRET, FLEET_NODE_LABEL (AC-4)
  - Files: plugins/specclaw-fleet/lib/dispatch.sh, plugins/specclaw-fleet/lib/manifest.sh, plugins/specclaw-fleet/lib/podspec.sh, plugins/specclaw-fleet/tests/cases/ac14_dispatch_inputs.sh
  - Kind: impl

### Wave 2 — delivery

- [ ] `T3` — GHCR multi-arch workflow and hosted pipeline template (AC-6, AC-9)
  - Files: .github/workflows/fleet-image.yml, plugins/specclaw-fleet/pipelines/dispatch-hosted.yml, plugins/specclaw-fleet/tests/cases/ac15_delivery.sh
  - Kind: config
- [ ] `T4` — `specclaw-fleet doctor`, read-only (AC-7)
  - Files: plugins/specclaw-fleet/lib/doctor.sh, plugins/specclaw-fleet/lib/doctor-checks.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/cases/ac16_doctor.sh
  - Kind: impl
- [ ] `T5` — `specclaw-fleet trigger` (AC-8)
  - Files: plugins/specclaw-fleet/lib/trigger.sh, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/cases/ac17_trigger.sh
  - Kind: impl
  - Depends: T2

### Wave 3 — skills and docs

- [ ] `T6` — setup and run skills; README (AC-10)
  - Files: plugins/specclaw-fleet/skills/setup/SKILL.md, plugins/specclaw-fleet/skills/run/SKILL.md, plugins/specclaw-fleet/README.md
  - Kind: docs
  - Depends: T1, T3, T4, T5

## Legend

- `[ ]` Pending · `[x]` Complete · `[!]` Failed
