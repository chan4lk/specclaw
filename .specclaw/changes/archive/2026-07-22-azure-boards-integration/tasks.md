# Tasks: Azure Boards integration for proposal tracking

**Change:** azure-boards-integration
**Created:** 2026-05-15
**Total Tasks:** 10

## Summary

New REST client script + new skill + config schema additions + lifecycle hooks added to 6 existing skills + auto-link in `specclaw-azdo-pr` + docs and CHANGELOG. All behavior is gated on `azdo.boards.sync: true` so default behavior is unchanged.

## Tasks

### Wave 1 — Foundation (parallelizable)

- [x] `T1` — Add `azdo.boards.*` block to config template
  - Files: `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Depends: —
  - Notes: Append a `boards:` sub-section under existing `azdo:` block with `sync: false`, `work_item_type: "Feature"`, `tag: "specclaw"` and comments explaining each key.

- [x] `T2` — Write `specclaw-azdo-issue` script (create + update + comment + close)
  - Files: `plugins/specclaw/bin/specclaw-azdo-issue`
  - Estimate: large
  - Depends: —
  - Notes: Model on `specclaw-jira-issue` for structure and on `specclaw-azdo-pr` for ADO REST calls. Use `application/json-patch+json` content-type for create/update. Use `sed_i` helper for status.md edits. Include `--help`. Bash 3.2 compatible. Exit 0 with stderr warning on idempotent no-op (Work Item already exists). Reads AZDO_TOKEN/AZDO_ORG/AZDO_PROJECT from `.specclaw/.env`; fails with friendly message pointing at `/specclaw:auth-azdo` if missing. Title truncation at 252+ellipsis. 30s curl timeout.

- [x] `T3` — Write `/specclaw:azdo-issue` skill
  - Files: `plugins/specclaw/skills/azdo-issue/SKILL.md`
  - Estimate: small
  - Depends: —
  - Notes: Model-invokable (no `disable-model-invocation`). Includes `specclaw-ensure-init` Step 0. Description: "Create or update an Azure Boards Work Item tracking this proposal. Mirrors /specclaw:issue for Jira but targets Azure DevOps. Requires /specclaw:auth-azdo first."

### Wave 2 — Lifecycle integration (depends on Wave 1)

- [x] `T4` — Hook `azdo-issue create` into `/specclaw:propose` SKILL.md
  - Files: `plugins/specclaw/skills/propose/SKILL.md`
  - Estimate: small
  - Depends: T2
  - Notes: After the existing GitHub-sync step, add a parallel step: "If `azdo.boards.sync: true`, run `specclaw-azdo-issue create .specclaw <change>` to create the Work Item."

- [x] `T5` — Hook `azdo-issue update` into `/specclaw:plan` SKILL.md
  - Files: `plugins/specclaw/skills/plan/SKILL.md`
  - Estimate: small
  - Depends: T2
  - Notes: After the existing GitHub-sync step, add: "If `azdo.boards.sync: true`, run `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the task checklist."

- [x] `T6` — Hook `azdo-issue comment` into `/specclaw:build` SKILL.md
  - Files: `plugins/specclaw/skills/build/SKILL.md`
  - Estimate: small
  - Depends: T2
  - Notes: At wave-end (after each wave's task statuses are updated) and on task failure (in addition to the existing gh-sync comment), add a conditional `specclaw-azdo-issue comment` call.

- [x] `T7` — Hook `azdo-issue comment` into `/specclaw:verify` SKILL.md
  - Files: `plugins/specclaw/skills/verify/SKILL.md`
  - Estimate: small
  - Depends: T2
  - Notes: After verify-report.md is written, add a conditional comment with the verdict summary.

- [x] `T8` — Hook `azdo-issue close` into `/specclaw:archive` SKILL.md
  - Files: `plugins/specclaw/skills/archive/SKILL.md`
  - Estimate: small
  - Depends: T2
  - Notes: Add a conditional `close` step.

- [x] `T9` — Auto-link PR to Work Item in `specclaw-azdo-pr`
  - Files: `plugins/specclaw/bin/specclaw-azdo-pr`
  - Estimate: medium
  - Depends: T2
  - Notes: After successful PR creation, if `azdo.boards.sync: true` and `status.md` contains `**Azure Boards Work Item:** [#...]`, PATCH the Work Item to add an `ArtifactLink` relation of type `Pull Request` with URL `vstfs:///Git/PullRequestId/{projectId}%2F{repoId}%2F{prId}`. Failure is a warning, not fatal — the PR already exists. Capture projectId and repoId from the PR-creation response (or look them up if needed).

### Wave 3 — Docs + release (depends on Wave 2)

- [x] `T10` — Docs, CHANGELOG, version bumps, manual smoke test
  - Files: `README.md`, `docs/index.md`, `docs/privacy.md`, `CHANGELOG.md`, `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: medium
  - Depends: T1-T9
  - Notes:
    - Bump plugin.json + marketplace.json from `0.2.5` → `0.3.0`.
    - CHANGELOG: new `[0.3.0]` section documenting Azure Boards integration.
    - README: add Azure Boards row to the integrations table.
    - docs/index.md: same.
    - docs/privacy.md: add Azure Boards to the "external services" enumeration.
    - **Manual smoke test** against `BistecGlobal/Agent-Accelerator`: run `specclaw-azdo-issue create` for this change, then `update`, then `comment "verify PASS"`, then confirm the Work Item is created with correct title/description/tag and the auto-link from a test PR works. Document outcomes in `verify-report.md` (next phase).

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**

    - [ ] `T<n>` — <title>
      - Files: <files to create/modify>
      - Estimate: small | medium | large
      - Depends: <task ids> (if any)
      - Notes: <additional context>
