# Tasks: only integration branches write the committed STATUS.md

**Change:** 057-status-integration-only
**Total Tasks:** 2

## Tasks

- [x] `T1` — update-status writes the committed STATUS.md only on integration branches, `--integration` or outside git, otherwise inside .git; readers use the printed path (AC-1)
  - Files: plugins/specclaw/bin/specclaw-update-status, plugins/specclaw/skills/status/SKILL.md, plugins/specclaw/references/full/status.md, plugins/specclaw-extras/skills/auto/SKILL.md, plugins/specclaw/tests/run-status-branch-tests.sh, plugins/specclaw/CLAUDE.md, .github/workflows/ci.yml
  - Kind: impl
- [x] `T2` — hosted pipeline refreshes STATUS.md on main/feature with [skip ci]; refused push warns (AC-2)
  - Files: plugins/specclaw-fleet/pipelines/dispatch-hosted.yml, plugins/specclaw-fleet/tests/cases/ac38_status_refresh.sh, plugins/specclaw-fleet/skills/setup/SKILL.md, plugins/specclaw-fleet/README.md
  - Kind: impl
