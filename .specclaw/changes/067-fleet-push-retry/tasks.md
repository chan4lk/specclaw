# Tasks: specclaw-fleet keeps a finished run when the push fails

**Change:** 067-fleet-push-retry
**Created:** 2026-11-16
**Total Tasks:** 4

## Summary

Retry the pod's push and report its failure (T1), mount a per-change bundle folder when asked (T2), save and resume unpushed work (T3), then doctor and docs (T4).

## Tasks

### Wave 1 — push retry and the Job mount

- [x] `T1` — Push retry, `exit=push-failed`, redacted `push_error` (AC-1, AC-2, AC-3, AC-4)
  - Files: plugins/specclaw-fleet/image/tracker.sh, plugins/specclaw-fleet/image/draft-pr.sh, plugins/specclaw-fleet/tests/lib/entry-env.sh, plugins/specclaw-fleet/tests/cases/ac40_push_retry.sh, plugins/specclaw-fleet/tests/cases/ac7_draft_pr.sh
  - Estimate: medium
  - Kind: backend
  - Context: 41000
  - Notes: FR-1, FR-2, FR-3. The git stub in entry-env.sh needs a way to fail the first N pushes and to log each push and repack call. Keep existing ac7 checks green.

- [x] `T2` — `bundle_claim` and `push_attempts` settings; claim volume, `subPath` and `fsGroup` in the Job; `node_label` required (AC-5, AC-6)
  - Files: plugins/specclaw-fleet/lib/settings.sh, plugins/specclaw-fleet/lib/podspec.sh, plugins/specclaw-fleet/lib/manifest.sh, plugins/specclaw-fleet/k8s/bundles-pvc.yaml, plugins/specclaw-fleet/tests/cases/ac14_dispatch_inputs.sh, plugins/specclaw-fleet/tests/cases/ac10_manifests.sh
  - Estimate: medium
  - Kind: backend
  - Context: 40000
  - Notes: FR-4, FR-5, FR-6, FR-11 (manifest only). Unset must render byte-identical output; pass FLEET_PUSH_ATTEMPTS to the pod env only when set.

### Wave 2 — bundles, doctor, docs

- [x] `T3` — Save a bundle on a failed push, resume from it, delete it after a good push (AC-7, AC-8, AC-9)
  - Files: plugins/specclaw-fleet/image/tracker.sh, plugins/specclaw-fleet/image/draft-pr.sh, plugins/specclaw-fleet/image/workspace.sh, plugins/specclaw-fleet/tests/lib/entry-env.sh, plugins/specclaw-fleet/tests/cases/ac41_bundles.sh
  - Estimate: medium
  - Kind: backend
  - Context: 40000
  - Depends: T1
  - Notes: FR-7, FR-8, FR-9. Bundle folder path comes from an env var defaulting to /fleet/bundles so tests can point it at a temp folder.

- [x] `T4` — `doctor` bundles line; README and setup skill (AC-10, AC-11)
  - Files: plugins/specclaw-fleet/lib/doctor.sh, plugins/specclaw-fleet/lib/doctor-checks.sh, plugins/specclaw-fleet/tests/cases/ac16_doctor.sh, plugins/specclaw-fleet/README.md, plugins/specclaw-fleet/skills/setup/SKILL.md
  - Estimate: small
  - Kind: backend
  - Context: 45000
  - Depends: T2
  - Notes: FR-10, FR-11 (docs). AC-12 is an operator check after a new image is published; record it as not run in verify.
