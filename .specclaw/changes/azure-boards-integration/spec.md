# Spec: Azure Boards integration for proposal tracking

**Change:** azure-boards-integration
**Created:** 2026-05-15
**Status:** 🟡 Draft

## Overview

Add Azure Boards as a third external tracker for specclaw proposals, symmetric to the existing GitHub Issues and Jira integrations. When enabled (`azdo.boards.sync: true`), each `/specclaw:propose` creates an ADO Work Item (default type `Feature`, tag `specclaw`) using the existing `/specclaw:auth-azdo` credentials. Subsequent lifecycle phases append progress to the Work Item via description updates and comments. `/specclaw:pr-azdo` auto-links the resulting pull request to the Work Item so it appears in the ADO "Development" panel.

specclaw does not auto-transition Work Item state — humans drive state machines in ADO because ADO process templates differ (Agile / Scrum / Basic), and the right transitions depend on team conventions.

## Requirements

### Functional Requirements

**FR1 — Create Work Item from proposal.** When `azdo.boards.sync: true`, `/specclaw:propose` invokes `specclaw-azdo-issue create .specclaw <change>` after writing `proposal.md`. The script POSTs a new Work Item to `https://dev.azure.com/{org}/{project}/_apis/wit/workitems/${WorkItemType}?api-version=7.1` with:
- `System.Title` = first non-header line of `proposal.md` (≤255 chars).
- `System.Description` = HTML-rendered body of `proposal.md`.
- `System.Tags` = `tag` from config (default `specclaw`).
- `System.AreaPath` = project default (no override).
- `System.IterationPath` = project default (no override).

**FR2 — Idempotent.** `specclaw-azdo-issue create` is idempotent: if `**Azure Boards Work Item:**` already appears in `status.md`, the script exits with a warning (exit 0) and does not create a duplicate.

**FR3 — Save Work Item reference.** On successful creation, append `**Azure Boards Work Item:** [#WI-1234](url)` to `.specclaw/changes/<change>/status.md`.

**FR4 — Update Work Item from plan.** `/specclaw:plan` invokes `specclaw-azdo-issue update .specclaw <change>` after writing `tasks.md`. The script PATCHes the existing Work Item's `System.Description` to include the rendered task checklist below the original proposal body.

**FR5 — Comment from build.** During `/specclaw:build`, after each wave completes, the build flow invokes `specclaw-azdo-issue comment .specclaw <change> "<progress summary>"`. On task failure, it invokes `specclaw-azdo-issue comment .specclaw <change> "❌ Task <id> failed: <summary>"`.

**FR6 — Comment from verify.** `/specclaw:verify` invokes `specclaw-azdo-issue comment .specclaw <change> "Verify <verdict>: <summary>"` after writing `verify-report.md`.

**FR7 — Closing comment on archive.** `/specclaw:archive` invokes `specclaw-azdo-issue close .specclaw <change>`. The script posts a final comment ("Change archived. PR: <url>") and adds a `closed-by-specclaw` tag. It does NOT change `System.State`.

**FR8 — Auto-link to ADO PR.** When `/specclaw:pr-azdo` opens a PR for a change whose `status.md` contains a Work Item ID, the script adds an `ArtifactLink` relation of type `Pull Request` to the Work Item so the PR appears under the Work Item's "Development" panel.

**FR9 — Config-driven enable.** All Azure Boards behavior is gated on `azdo.boards.sync: true` in `config.yaml`. With `sync: false` or the section absent, none of the lifecycle hooks fire; behavior is identical to today.

**FR10 — Config schema.**
```yaml
azdo:
  org: ""           # existing — set by /specclaw:auth-azdo
  project: ""       # existing
  repo: ""          # existing
  boards:
    sync: false               # NEW: default off
    work_item_type: "Feature" # NEW: "Feature" | "User Story" | "Task" | "Bug" | "Epic"
    tag: "specclaw"           # NEW: comma-separated for multiple tags
```

**FR11 — New skill `/specclaw:azdo-issue`.** Mirrors `/specclaw:issue` (Jira). Frontmatter has a `description` field and is **model-invokable** (no `disable-model-invocation`) since this just creates issues and isn't credential-sensitive.

**FR12 — Reuse existing auth.** No new auth flow. The script reads `AZDO_TOKEN`, `AZDO_ORG`, `AZDO_PROJECT` from `.specclaw/.env`. If those are missing, exit with a clear pointer to `/specclaw:auth-azdo`.

**FR13 — README + docs update.** Add Azure Boards to the integrations list on the README, the landing page (`docs/index.md`), and the privacy policy's "external services" section.

### Non-Functional Requirements

**NFR1 — Symmetry with existing integrations.** The script's subcommand surface, exit codes, and idempotency behavior match `specclaw-jira-issue` and `specclaw-gh-sync` as closely as possible. Same CLI shape, same logging style.

**NFR2 — Backwards compatibility.** Default behavior unchanged. Users who don't add `azdo.boards.sync: true` see no difference.

**NFR3 — BSD/GNU sed portability.** Any new in-place edits use the `sed_i` helper introduced in v0.2.5.

**NFR4 — Bash 3.2 compatibility.** No associative arrays.

## Acceptance Criteria

**AC1 —** `plugins/specclaw/bin/specclaw-azdo-issue` exists, is executable, has `#!/usr/bin/env bash` shebang, and supports subcommands `create`, `update`, `comment`, `close`. `specclaw-azdo-issue --help` lists them without error.

**AC2 —** `plugins/specclaw/skills/azdo-issue/SKILL.md` exists with valid frontmatter (`description:` present, no `disable-model-invocation`).

**AC3 —** `plugins/specclaw/templates/config.yaml` includes the new `azdo.boards` block with `sync`, `work_item_type`, `tag` keys.

**AC4 —** With `azdo.boards.sync: false` (default), running `/specclaw:propose` produces no ADO API calls and the proposal flow is identical to today.

**AC5 —** With `azdo.boards.sync: true` and valid ADO credentials, `specclaw-azdo-issue create .specclaw azure-boards-integration` POSTs to the ADO REST API and prints `Created Work Item #N: <url>`. (Manual smoke test against the BistecGlobal/Agent-Accelerator ADO instance.)

**AC6 —** A second invocation of `create` for the same change prints `WARNING: Work Item already created: #N` and exits 0.

**AC7 —** After step AC5, `status.md` contains a line matching `^\*\*Azure Boards Work Item:\*\* \[#WI-\d+\]\(https://.*\)$`.

**AC8 —** `specclaw-azdo-issue update .specclaw <change>` PATCHes the Work Item's description and prints `Updated Work Item #N`.

**AC9 —** `specclaw-azdo-issue comment .specclaw <change> "test"` adds a comment via the ADO comments API and prints `Commented on Work Item #N`.

**AC10 —** When `/specclaw:pr-azdo` runs for a change with a Work Item ID, the ADO PR's "Related Work Items" section lists the Work Item.

**AC11 —** With missing `AZDO_TOKEN`, the script exits with: `ERROR: Azure DevOps credentials missing — run /specclaw:auth-azdo`.

**AC12 —** README, `docs/index.md`, and `docs/privacy.md` list Azure Boards as a supported integration.

**AC13 —** CHANGELOG `[0.3.0]` entry documents the new integration.

## Edge Cases

**EC1 — `sync: true` but auth not set up.** Script exits with a friendly error pointing at `/specclaw:auth-azdo`, lifecycle continues (proposal still drafted locally).

**EC2 — Work item type doesn't exist in the project's process template.** ADO returns 400. Script captures the error message verbatim and exits 1, leaving `status.md` unchanged.

**EC3 — Title >255 chars.** Truncate at 252 + `…` (ADO max title length).

**EC4 — User runs `update` before `create`.** No Work Item ID in `status.md` → script exits 1 with message: `ERROR: No Work Item for this change — run specclaw-azdo-issue create first`.

**EC5 — Network failure mid-flow.** All HTTP calls have a 30s timeout. On failure, the script exits non-zero with the curl error preserved; lifecycle continues but the Work Item isn't updated.

**EC6 — Multiple tags via config.** `tag: "specclaw, priority-high"` passes through as two tags.

## Dependencies

- `curl` (existing dep, already used by `specclaw-jira-issue` and `specclaw-azdo-pr`)
- `jq` (existing optional dep — used for parsing ADO REST JSON responses)
- `/specclaw:auth-azdo` having been run once

No new external dependencies.

## Notes

- The ADO REST API for Work Items uses `application/json-patch+json` (not `application/json`) for create/update — the patch format is `[{"op":"add","path":"/fields/System.Title","value":"..."}]`. Existing `specclaw-azdo-pr` already uses curl against the ADO REST API; the new script follows the same idiom.
- Comments use `https://dev.azure.com/{org}/{project}/_apis/wit/workItems/{id}/comments?api-version=7.1-preview.3` with a plain JSON body.
- "Auto-link to PR" uses the relations API: `PATCH /workitems/{id}` with `op: add, path: /relations/-, value: {rel: "ArtifactLink", url: "vstfs:///Git/PullRequestId/{projectId}%2F{repoId}%2F{prId}", attributes: {name: "Pull Request"}}`.
