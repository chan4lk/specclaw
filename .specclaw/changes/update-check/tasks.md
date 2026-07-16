# Tasks: Plugin Update Check

**Change:** update-check
**Created:** 2026-07-16
**Total Tasks:** 4

## Summary

Script first (everything depends on it), then tests + config in parallel, wiring + docs last.

## Tasks

### Wave 1 — Core script

- [x] `T1` — Implement `specclaw-check-update`
  - Files: plugins/specclaw/bin/specclaw-check-update
  - Estimate: medium
  - Depends: —
  - Notes: Per design.md flow: gate on plugin.update_check (absent=true); local version from SCRIPT_DIR/../.claude-plugin/plugin.json; --remote-version bypasses cache+network; daily cache <specclaw_dir>/.update-check (epoch + version, corrupt=stale); curl -fsS --max-time 5 raw marketplace.json (main then master), specclaw-block version extraction jq-free; pad-to-3 numeric semver compare; newer → single ⬆ line with /plugin update specclaw; every failure exit 0 silent. bash -3.2 safe, no jq.

### Wave 2 — Tests + config

- [x] `T2` — Offline test cases
  - Files: plugins/specclaw/tests/run-parser-tests.sh
  - Estimate: small
  - Depends: T1
  - Notes: Case 8: AC1 newer --remote-version prints one line (contains both versions + '/plugin update specclaw'); AC2 equal + older silent; AC3 update_check:false beats newer hook; AC4 unreachable repository URL (https://invalid.invalid/x/y) silent exit 0; AC5 cache: seed fresh cache with newer version + unreachable repo → notification from cache without network; corrupt cache ignored. All offline.

- [x] `T3` — Config template key
  - Files: plugins/specclaw/templates/config.yaml
  - Estimate: small
  - Depends: T1
  - Notes: New `plugin:` block, `update_check: true` commented (what it does, how to disable, cache file location + gitignore advice).

### Wave 3 — Wiring + release

- [x] `T4` — Status wiring, README, CHANGELOG, version
  - Files: plugins/specclaw/skills/status/SKILL.md, README.md, CHANGELOG.md, plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Depends: T1, T2, T3
  - Notes: status SKILL: run specclaw-check-update .specclaw after dashboard, surface printed line verbatim, ignore empty. README: "Update check" note under Configuration (behavior, off switch, gitignore .specclaw/.update-check). CHANGELOG: bullet appended under [0.5.1] (single release for the open PR batch). Version 0.5.1 both files.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:** see the tasks above for the live shape — checkbox, ID, title, then `Files / Estimate / Depends / Notes` sub-bullets.
