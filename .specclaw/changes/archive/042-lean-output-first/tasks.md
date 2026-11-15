# Tasks: Lean, output-first greenfield flow

**Change:** 042-lean-output-first
**Created:** 2026-10-11
**Total Tasks:** 16

## Summary

Four stages as ordered waves. Waves 1–2 deliver the lean flow (Stage 1). Waves 3–4 split the plugin and trim it (Stage 2). Wave 5 adds presets (Stage 3). Wave 6 adds the quality scan (Stage 4).

## Tasks

### Wave 1 — Lean mechanics

- [x] `T1` — `specclaw-flow` + config keys + lean `init`
  - Files: plugins/specclaw/bin/specclaw-flow, plugins/specclaw/bin/specclaw-init, plugins/specclaw/templates/config.yaml
  - Estimate: small
  - Kind: impl
  - Notes: FR-1, FR-2. Add `flow`, `presets: []`, `preset_overrides: {}` to the template. `init` writes `flow: lean` + lean defaults and copies the mock template.
- [x] `T2` — Lean templates: `change.md` and `mock.html`
  - Files: plugins/specclaw/templates/lean/change.md, plugins/specclaw/templates/lean/mock.html
  - Estimate: small
  - Kind: docs
  - Notes: FR-3, design decision 4. mock.html is self-contained with no external URLs, a nav built from `data-change` sections, and inline fake data.
- [x] `T3` — Lean awareness in validate/parse/status/reconcile
  - Files: plugins/specclaw/bin/specclaw-validate-change, plugins/specclaw/bin/specclaw-parse-tasks, plugins/specclaw/bin/specclaw-update-status, plugins/specclaw/bin/specclaw-reconcile
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: FR-4, design decision 3. Refuse mixed artifact sets.
- [x] `T4` — `specclaw-screenshot`
  - Files: plugins/specclaw/bin/specclaw-screenshot
  - Estimate: small
  - Kind: impl
  - Notes: FR-8, design decision 5. Exit 3 when Playwright is unavailable.

### Wave 2 — Lean skills + Stage 1 tests

- [x] `T5` — Dispatcher skills + `references/full/`
  - Files: plugins/specclaw/skills/{init,propose,plan,build,verify,pr,status,archive}/SKILL.md, plugins/specclaw/references/full/*.md
  - Estimate: large
  - Kind: docs
  - Depends: T1, T2, T3, T4
  - Notes: FR-5..FR-10, NFR-1. Move each 0.7.9 body verbatim to references/full/<phase>.md, then write ≤300 words of lean text plus the dispatch line. Leave the brownfield sections in references/full/propose.md for now; T7 moves them.
- [x] `T6` — `run-lean-flow-tests.sh`
  - Files: plugins/specclaw/tests/run-lean-flow-tests.sh, .github/workflows/ci.yml
  - Estimate: small
  - Kind: test
  - Depends: T5
  - Notes: AC-1..AC-5, one case each.

### Wave 3 — Plugin split

- [x] `T7` — Create `specclaw-bf`
  - Files: plugins/specclaw-bf/** (git mv of bf-* skills, agents, bins, templates, references, tests), plugins/specclaw-bf/skills/propose/SKILL.md, plugins/specclaw/references/full/propose.md
  - Estimate: large
  - Kind: refactor
  - Depends: T5
  - Notes: FR-12, design decision 7. Remove the gate sections from core propose; the bf propose runs them, then hands over to specclaw:propose.
- [x] `T8` — Create `specclaw-sync`
  - Files: plugins/specclaw-sync/** (git mv sync skills, bins, tests), core skills/references sync call sites
  - Estimate: medium
  - Kind: refactor
  - Depends: T5
  - Notes: FR-13. Put every core call site behind `command -v`.
- [x] `T9` — Create `specclaw-extras`
  - Files: plugins/specclaw-extras/** (git mv extras skills, party/spec-author agents, specclaw-party, related bins and tests)
  - Estimate: medium
  - Kind: refactor
  - Depends: T5
  - Notes: FR-14. `specclaw-loop` stays in core.
- [x] `T10` — Manifests, marketplaces, shared version, CI, Codex
  - Files: plugins/*/.claude-plugin/plugin.json, plugins/*/.codex-plugin/plugin.json, .claude-plugin/marketplace.json, .agents/plugins/marketplace.json, .agents/skills/specclaw/SKILL.md, .github/workflows/ci.yml, .specclaw/config.yaml (plugin.version_files), plugins/specclaw/tests/run-codex-plugin-tests.sh, plugins/specclaw/tests/run-codex-skill-tests.sh, plugins/specclaw/tests/run-plugin-split-tests.sh
  - Estimate: medium
  - Kind: config
  - Depends: T7, T8, T9
  - Notes: FR-11, FR-15. AC-6, AC-7, AC-14.

### Wave 4 — Notice + trim

- [x] `T11` — Missing-plugin notice in the session-start hook
  - Files: plugins/specclaw/hooks/session-start, plugins/specclaw/tests/run-bootstrap-hook-tests.sh
  - Estimate: small
  - Kind: impl
  - Depends: T10
  - Notes: FR-16, AC-8.
- [x] `T12` — Trim descriptions, README, docs
  - Files: plugins/*/skills/*/SKILL.md (frontmatter only), plugins/*/agents/*.md (frontmatter only), README.md, docs/index.md, CHANGELOG.md, .specclaw/context.md, plugins/specclaw/tests/description-lint-baseline.txt
  - Estimate: medium
  - Kind: docs
  - Depends: T10
  - Notes: FR-17, AC-9. The baseline only shrinks.

### Wave 5 — Presets

- [x] `T13` — Preset files
  - Files: plugins/specclaw/presets/{base,python,nextjs,node,dotnet,react-spa}.md
  - Estimate: medium
  - Kind: docs
  - Depends: T5
  - Notes: FR-18, ≤60 lines each, with each preset's shared-library location (used by T16).
- [x] `T14` — `specclaw-preset-check` + init detection + build/verify wiring
  - Files: plugins/specclaw/bin/specclaw-preset-check, plugins/specclaw/bin/specclaw-init, plugins/specclaw/skills/{build,verify}/SKILL.md, plugins/specclaw/tests/run-preset-check-tests.sh, .github/workflows/ci.yml
  - Estimate: medium
  - Kind: impl
  - Depends: T13
  - Notes: FR-19..FR-21, design decision 9. AC-10, AC-11.

### Wave 6 — Quality scan

- [x] `T15` — Extract `specclaw-quality-scan`
  - Files: plugins/specclaw/bin/specclaw-quality-scan, plugins/specclaw-bf/bin/specclaw-bf-quality-collect, plugins/specclaw/tests/run-quality-scan-tests.sh, .github/workflows/ci.yml
  - Estimate: medium
  - Kind: refactor
  - Depends: T7
  - Notes: FR-22, design decision 10. AC-12, AC-13.
- [x] `T16` — Refactor step in lean build + quality gate in lean verify
  - Files: plugins/specclaw/skills/build/SKILL.md, plugins/specclaw/skills/verify/SKILL.md, plugins/specclaw/templates/lean/change.md
  - Estimate: small
  - Kind: docs
  - Depends: T14, T15
  - Notes: FR-23, FR-24, design decision 11. Keep the build skill ≤300 words.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred
