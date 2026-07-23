# Proposal: Azure Boards integration for proposal tracking

**Created:** 2026-05-15
**Status:** 🟡 Draft

## Problem

specclaw currently supports two external trackers for proposals:

- **GitHub Issues** — via `specclaw-gh-sync` (creates issues, updates checklists, posts comments through the lifecycle, closes on archive).
- **Jira** — via `specclaw-jira-issue` (creates issues from proposals using the Atlassian REST API).

Teams whose project management lives in **Azure Boards** (the work-item side of Azure DevOps) have no first-class option. They can:
1. Use GitHub Issues anyway — fragments the team across two trackers.
2. Use Jira — extra subscription, extra tool, extra context-switch.
3. Skip external tracking entirely — loses visibility for stakeholders who don't read `.specclaw/`.

We already authenticate against Azure DevOps for `/specclaw:pr-azdo`. Adding a parallel **work-item** integration uses the same PAT, the same `azdo.org` and `azdo.project`, and gives ADO-native teams the same proposal-tracking story GitHub and Jira users get.

## Proposed Solution

Add a third tracker integration, symmetric in shape to the existing two:

1. **`specclaw-azdo-issue`** — new lifecycle script (mirrors `specclaw-jira-issue` and `specclaw-gh-sync`). Subcommands:
   - `create .specclaw <change>` — create a Work Item from `proposal.md`.
   - `update .specclaw <change>` — refresh the description with current task checklist from `tasks.md`.
   - `comment .specclaw <change> "<text>"` — post a comment (verify result, error log, etc.).
   - `close .specclaw <change>` — set the Work Item state to Closed/Done on archive.

2. **`/specclaw:azdo-issue`** — new skill (parallels `/specclaw:issue` for Jira). Idempotent: warns and skips if `azdo_work_item_id` already in `status.md`.

3. **Config additions** under the existing `azdo:` section in `config.yaml`:
   ```yaml
   azdo:
     org: "BistecGlobal"           # already used by /specclaw:pr-azdo
     project: "Agent-Accelerator"  # already used by /specclaw:pr-azdo
     repo: "agent-nexus"           # already used by /specclaw:pr-azdo
     boards:
       sync: true                  # ← NEW: enables Azure Boards integration
       work_item_type: "User Story" # ← NEW: "User Story" | "Task" | "Bug" | "Feature"
       tag: "specclaw"             # ← NEW: tag added to every specclaw-created Work Item
   ```

4. **Lifecycle hooks**: when `azdo.boards.sync: true`:
   - `propose` calls `specclaw-azdo-issue create` after generating `proposal.md`.
   - `plan` calls `specclaw-azdo-issue update` after writing `tasks.md`.
   - `build` calls `update` after each completed wave, `comment` on task failures.
   - `verify` calls `comment` with the verdict summary.
   - `archive` calls `close`.

5. **Credentials**: reuse `AZDO_TOKEN`, `AZDO_ORG`, `AZDO_PROJECT` from `.specclaw/.env` set by `/specclaw:auth-azdo`. No new auth flow required.

## Scope

### In Scope
- `plugins/specclaw/bin/specclaw-azdo-issue` — REST API client targeting `https://dev.azure.com/{org}/{project}/_apis/wit/workitems/${WorkItemType}?api-version=7.1`
- `plugins/specclaw/skills/azdo-issue/SKILL.md`
- `azdo.boards.{sync,work_item_type,tag}` config keys in `templates/config.yaml`
- Hooks added to `propose`, `plan`, `build`, `verify`, `archive` SKILL.md files (conditional on `azdo.boards.sync`)
- `**Azure Boards Work Item:** [WI-1234](url)` line appended to `status.md`
- README + docs landing page: add Azure Boards to the integrations list

### Out of Scope
- Bidirectional sync (Azure Boards → specclaw) — one-way only, like GitHub/Jira today
- Custom field mapping beyond title, description, tag, state
- Iteration path / area path management — defaults to project root
- Real-time webhook listening for state changes pushed from ADO
- Mirroring sub-tasks 1:1 to ADO child Work Items (the parent Work Item gets a markdown checklist instead)
- Migration tooling for existing changes that don't have an ADO Work Item

## Impact

- **Files affected:** ~10 (2 new: `bin/specclaw-azdo-issue` and `skills/azdo-issue/SKILL.md`; 5 SKILL.md updates for lifecycle hooks; config template; CHANGELOG; README; docs landing page).
- **Complexity:** medium — REST API client is mechanical (mirrors existing `specclaw-jira-issue`), the touchier work is the lifecycle hook fan-out.
- **Risk:** low — additive, opt-in via `azdo.boards.sync` flag, defaults to disabled.

## Decisions

1. **Default work item type:** `Feature` (overridable via `azdo.boards.work_item_type`).
2. **Tag:** default `specclaw` (overridable via `azdo.boards.tag`). Comma-separated tags pass through.
3. **State transitions:** specclaw does **not** auto-transition Work Item state. State machines differ per ADO process template (Agile/Scrum/Basic) — auto-transitioning is too easy to get wrong. specclaw only writes description, comments, tags, and the closing comment. Humans drive state in ADO.
4. **Auto-link Work Item ↔ ADO PR:** when `/specclaw:pr-azdo` runs for a change that has a Work Item ID in `status.md`, attach the PR to the Work Item via the ADO REST relations API (`ArtifactLink` of type `Pull Request`) so the PR shows under the Work Item's "Development" panel.
5. **Version:** v0.3.0 (minor bump — additive new feature).

---

**Approved 2026-05-15.** Proceeding to `/specclaw:plan`.
