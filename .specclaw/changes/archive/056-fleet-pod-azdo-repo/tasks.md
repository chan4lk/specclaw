# Tasks: specclaw-fleet pod never sets AZDO_REPO

**Change:** 056-fleet-pod-azdo-repo
**Total Tasks:** 1

## Tasks

- [x] `T1` — Pod exports AZDO_REPO from FLEET_REPO_URL unless already set; entrypoint test covers derived and preset values
  - Files: plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/tests/lib/entry-env.sh, plugins/specclaw-fleet/tests/cases/ac7_entrypoint.sh
  - Kind: impl
