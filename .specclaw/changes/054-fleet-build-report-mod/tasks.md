# Tasks: specclaw-fleet build report and mod

**Change:** 054-fleet-build-report-mod
**Created:** 2026-11-09
**Total Tasks:** 5

## Tasks

### Wave 1: data

- [x] `T1` — Durable run fields: `pipeline_run` on dispatch, agent times/cost/turns/model/review rounds/commits on the final pod record (AC-1)
  - Files: plugins/specclaw-fleet/image/run-stats.sh, plugins/specclaw-fleet/image/entrypoint.sh, plugins/specclaw-fleet/image/draft-pr.sh, plugins/specclaw-fleet/lib/launch.sh, plugins/specclaw-fleet/tests/cases/ac34_run_stats.sh
  - Kind: impl
- [x] `T2` — `specclaw-fleet report` with `--json`, `--html`, `--save`, `--since`, `--feature` (AC-2, AC-3)
  - Files: plugins/specclaw-fleet/lib/report.sh, plugins/specclaw-fleet/lib/report-render.sh, plugins/specclaw-fleet/lib/report.html, plugins/specclaw-fleet/bin/specclaw-fleet, plugins/specclaw-fleet/tests/cases/ac35_report.sh
  - Kind: impl
  - Depends: T1

### Wave 2: mod

- [x] `T3` — Mod core: snapshot parse/validate, timeline, pane, band, status (AC-4)
  - Files: plugins/specclaw-fleet/hooks/core/report.ts, plugins/specclaw-fleet/hooks/core/view.ts, plugins/specclaw-fleet/tests/report.spec.ts
  - Kind: impl
  - Depends: T2
- [x] `T4` — Mod wiring: `/fleet-pane`, band, status line, refresh after fleet Bash calls; manifest, types, mod test runner, CI (AC-5)
  - Files: plugins/specclaw-fleet/hooks/mod.json, plugins/specclaw-fleet/hooks/register.tsx, plugins/specclaw-fleet/hooks/snapshot.ts, plugins/specclaw-fleet/types/index.d.ts, plugins/specclaw-fleet/.claude-plugin/plugin.json, plugins/specclaw-fleet/tests/fixtures.ts, plugins/specclaw-fleet/tests/pane.test.tsx, plugins/specclaw-fleet/tests/run-mod-tests.sh, .github/workflows/ci.yml
  - Kind: impl
  - Depends: T3

### Wave 3: docs

- [ ] `T5` — `/specclaw-fleet:report` skill and README section (AC-6)
  - Files: plugins/specclaw-fleet/skills/report/SKILL.md, plugins/specclaw-fleet/README.md, plugins/specclaw-fleet/tests/cases/ac26_skills.sh
  - Kind: docs
  - Depends: T2, T4

## Legend

- `[ ]` pending · `[~]` in progress · `[x]` complete · `[!]` failed
