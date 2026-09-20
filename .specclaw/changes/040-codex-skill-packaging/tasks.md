# Tasks: Package SpecClaw as a Codex Skill Alongside Claude

**Change:** 040-codex-skill-packaging
**Created:** 2026-09-20
**Total Tasks:** 4 across 3 waves

## Summary

Add a single repository-local Codex adapter that delegates to the existing SpecClaw plugin, prove that delegation remains canonical, then document and gate it in CI. The worktree branch is `specclaw/040-codex-skill-packaging`.

## Tasks

### Wave 1 — Failing validation

- [x] `T1` — Add failing validation for the Codex skill adapter
  - Files: `plugins/specclaw/tests/run-codex-skill-tests.sh` (create)
  - Estimate: small
  - Kind: test
  - Notes: Test valid frontmatter; repository/plugin-root resolution; every routed canonical verb exists; helpers are resolved from `plugins/specclaw/bin/`; no copied `skills`, `bin`, `templates`, or `references` payload exists in `.agents/skills/specclaw`; and Claude manifests/canonical skill documents are outside the adapter's changed file set.

### Wave 2 — Canonical Codex adapter

- [x] `T2` — Create the repository-local Codex SpecClaw adapter
  - Files: `.agents/skills/specclaw/SKILL.md` (create)
  - Estimate: medium
  - Kind: impl
  - Depends: T1
  - Notes: Use concise `specclaw` frontmatter and instructions that resolve the checkout at runtime, delegate to `plugins/specclaw/skills/<verb>/SKILL.md`, invoke helpers via `plugins/specclaw/bin/`, and preserve canonical plugin-root resource resolution. Do not alter Claude manifests or canonical Claude skills.

### Wave 3 — Documentation and CI enforcement

- [x] `T3` — Document Codex checkout-local installation and use
  - Files: `README.md` (modify), `docs/index.md` (modify), `CONTRIBUTING.md` (modify)
  - Estimate: small
  - Kind: docs
  - Depends: T2
  - Notes: Add the Codex repository-local path and `$specclaw` invocation while preserving all existing Claude Code marketplace/install guidance verbatim in meaning. State that this change does not install a global skill.

- [x] `T4` — Register and run the Codex adapter validation
  - Files: `.github/workflows/ci.yml` (modify)
  - Estimate: small
  - Kind: test
  - Depends: T1, T2
  - Notes: Add the focused suite to the existing CI test job, run it locally, and run the existing relevant regression suite to demonstrate no Claude packaging regression.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed
- `[>]` Deferred — correctly blocked on a sibling change, not incomplete through any fault of its own; excluded from the incomplete-task count that gates `verify`
