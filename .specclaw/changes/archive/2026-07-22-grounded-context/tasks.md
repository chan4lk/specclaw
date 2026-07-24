# Tasks: Grounded Context Discovery

**Change:** grounded-context
**Created:** 2026-07-16
**Total Tasks:** 6

## Summary

Build the discovery script first (T1 — everything depends on it), then fan out: tests, config template, and plan-skill wiring in parallel (Wave 2), payload-builder integration next (Wave 3), and release plumbing last (Wave 4) so docs and version reflect the finished state.

## Tasks

### Wave 1 — Core discovery script

- [x] `T1` — Implement `specclaw-discover-context` (list + emit modes)
  - Files: plugins/specclaw/bin/specclaw-discover-context
  - Estimate: large
  - Depends: —
  - Notes: Modes per design.md API. Enumerate via `git ls-files -z` with `find` fallback; null-delimited iteration (space-safe). Ranking tiers 1–5 (llms.txt → root canonical → doc dirs → nested README/CLAUDE → other .md), alphabetical within tier. Default exclusions incl. `.specclaw/`, changelog/license/CoC variants, archive/deprecated/i18n, node_modules/vendor/dist/build. Config precedence: exclude > folders > include; `pin` bypasses ranking. Budget in emit mode: rank-order accumulation, boundary-file truncation, `<!-- dropped: ... -->` footer naming every casualty. `discovery: false` or no candidates → exit 0, empty stdout. Reuse existing `yaml_val` helper pattern from sibling scripts. Plain bash + coreutils, jq-free, BSD/GNU-sed safe.

### Wave 2 — Parallel wiring

- [x] `T2` — Discovery test cases + fixtures
  - Files: plugins/specclaw/tests/run-parser-tests.sh, plugins/specclaw/tests/fixtures/discovery/
  - Estimate: medium
  - Depends: T1
  - Notes: Fixture tree: root README.md + CLAUDE.md, docs/guide.md, src/README.md, CHANGELOG.md, archive/old.md, llms.txt referencing docs/guide.md + one missing path. Cases: AC1 ranking, AC2 llms.txt priority + missing-path warning, AC3 default exclusions, AC4 precedence + glob/root-relative patterns, AC5 budget drop/truncate footer, AC6 discovery-off empty output, non-git fallback (run fixture outside git via temp dir). Follow existing plain-bash test style (mktemp -d workspace, pass/fail counters).

- [x] `T3` — `context:` config block in template
  - Files: plugins/specclaw/templates/config.yaml
  - Estimate: small
  - Depends: T1
  - Notes: Add commented block (discovery/max_lines/folders/pin/exclude) with defaults per spec FR7. Comment each field incl. pattern syntax summary and precedence rule. Additive only — existing keys untouched.

- [x] `T4` — Plan skill grounding steps
  - Files: plugins/specclaw/skills/plan/SKILL.md
  - Estimate: medium
  - Depends: T1
  - Notes: Insert after current step 3 (codebase analysis): (a) structured codebase survey instructions (top-2-level dir summary, manifest detection list from design.md, test layout); (b) run `specclaw-discover-context .specclaw list` then `emit` and include digest in planning payload; (c) read `.specclaw/knowledge/spec-guidelines.md` if present and apply during spec generation (FR8/AC9); (d) require "Grounding sources" section in generated design.md listing selected docs. Keep --author-spec flow intact; all new steps no-op gracefully when discovery off/empty.

### Wave 3 — Payload builders

- [x] `T5` — Inject digest into build + verify payloads
  - Files: plugins/specclaw/bin/specclaw-build-context, plugins/specclaw/bin/specclaw-verify-context
  - Estimate: medium
  - Depends: T1, T3
  - Notes: Call `specclaw-discover-context "$SPECCLAW_DIR" emit`; if non-empty, append delimited section `## Discovered Project Docs` AFTER Project Context and Repo Knowledge Base sections (curated-first priority, design decision 5). Empty output → no section header (NFR2 byte-identical). Mirror existing section-building style (see KNOWLEDGE_SECTION pattern at build-context:264).

### Wave 4 — Release plumbing

- [x] `T6` — README, CHANGELOG, version bump
  - Files: README.md, CHANGELOG.md, plugins/specclaw/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Estimate: small
  - Depends: T2, T3, T4, T5
  - Notes: README: new "Grounded context" subsection documenting the `context:` block, ranking tiers, llms.txt support, exclusions + precedence; refresh stale config example if present. CHANGELOG: Added entry under new patch version. Bump version in both JSON files (keep in sync). Last so docs describe the finished behavior.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:** see the tasks above for the live shape — checkbox, ID, title, then `Files / Estimate / Depends / Notes` sub-bullets.
