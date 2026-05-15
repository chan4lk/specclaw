# Design: Azure Boards integration for proposal tracking

**Change:** azure-boards-integration
**Created:** 2026-05-15

## Technical Approach

A new lifecycle script `specclaw-azdo-issue` modeled directly on `specclaw-jira-issue` (existing) and `specclaw-gh-sync` (existing). It implements four subcommands — `create`, `update`, `comment`, `close` — each a single curl call to the ADO REST API plus a small amount of bash glue. The script reuses `AZDO_TOKEN` / `AZDO_ORG` / `AZDO_PROJECT` already populated in `.specclaw/.env` by `/specclaw:auth-azdo`.

Lifecycle integration is gated behind `azdo.boards.sync` in config. When enabled, the existing `propose`, `plan`, `build`, `verify`, `pr-azdo`, and `archive` SKILL.md files invoke the new script at well-defined points (mirroring how they invoke `specclaw-gh-sync` and `specclaw-jira-issue` today). No state machine in specclaw — the script only writes description, comments, tags, and (on `pr-azdo`) an ArtifactLink relation.

The auto-link from PR → Work Item happens inside `specclaw-azdo-pr` (existing script): after the PR is created, if `status.md` contains an Azure Boards Work Item ID, it PATCHes the Work Item to attach the PR via the `ArtifactLink` relation.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Existing lifecycle skills (propose, plan, build, verify, pr-azdo,       │
│  archive) — each gains a conditional call when `azdo.boards.sync: true`  │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  plugins/specclaw/bin/specclaw-azdo-issue                                │
│  ────────────────────────────────────────                                │
│  Subcommands:                                                            │
│    create  <specclaw_dir> <change>           — POST a new Work Item      │
│    update  <specclaw_dir> <change>           — PATCH description         │
│    comment <specclaw_dir> <change> "<text>"  — POST a comment            │
│    close   <specclaw_dir> <change>           — final comment + tag       │
│                                                                          │
│  Reads:                                                                  │
│    .specclaw/.env → AZDO_TOKEN, AZDO_ORG, AZDO_PROJECT                   │
│    config.yaml   → azdo.boards.{sync,work_item_type,tag}                 │
│    proposal.md, spec.md, tasks.md, status.md, verify-report.md           │
│                                                                          │
│  Writes:                                                                 │
│    status.md → **Azure Boards Work Item:** [#N](url)                     │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (curl + jq)
┌──────────────────────────────────────────────────────────────────────────┐
│  ADO REST API                                                            │
│   POST   /wit/workitems/${TYPE}    — create                              │
│   PATCH  /wit/workitems/{id}       — update description / add relation   │
│   POST   /wit/workItems/{id}/comments — comment                          │
└──────────────────────────────────────────────────────────────────────────┘
```

```
plugins/specclaw/
├── bin/
│   ├── specclaw-azdo-issue            ← NEW
│   └── specclaw-azdo-pr               ← MODIFIED (auto-link to Work Item)
├── skills/
│   ├── azdo-issue/SKILL.md            ← NEW
│   ├── propose/SKILL.md               ← MODIFIED (conditional create call)
│   ├── plan/SKILL.md                  ← MODIFIED (conditional update call)
│   ├── build/SKILL.md                 ← MODIFIED (conditional comment calls)
│   ├── verify/SKILL.md                ← MODIFIED (conditional comment call)
│   └── archive/SKILL.md               ← MODIFIED (conditional close call)
└── templates/
    └── config.yaml                    ← MODIFIED (azdo.boards.* block)
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-azdo-issue` | **add** | New REST client with create/update/comment/close subcommands |
| `plugins/specclaw/skills/azdo-issue/SKILL.md` | **add** | Model-invokable skill mirroring `/specclaw:issue` for Jira |
| `plugins/specclaw/templates/config.yaml` | **modify** | Add `azdo.boards.{sync,work_item_type,tag}` block |
| `plugins/specclaw/bin/specclaw-azdo-pr` | **modify** | After PR creation, if Work Item ID exists in status.md, attach ArtifactLink relation |
| `plugins/specclaw/skills/propose/SKILL.md` | **modify** | Step: `if azdo.boards.sync, specclaw-azdo-issue create` |
| `plugins/specclaw/skills/plan/SKILL.md` | **modify** | Step: `if azdo.boards.sync, specclaw-azdo-issue update` |
| `plugins/specclaw/skills/build/SKILL.md` | **modify** | Wave-end and task-fail: conditional comment calls |
| `plugins/specclaw/skills/verify/SKILL.md` | **modify** | After verdict: conditional comment call |
| `plugins/specclaw/skills/archive/SKILL.md` | **modify** | Step: `if azdo.boards.sync, specclaw-azdo-issue close` |
| `README.md` | **modify** | Add Azure Boards to integrations list |
| `docs/index.md` | **modify** | Add Azure Boards row to integrations table / mentions |
| `docs/privacy.md` | **modify** | Add Azure Boards to "external services" section |
| `CHANGELOG.md` | **modify** | Add `[0.3.0]` entry |
| `plugins/specclaw/.claude-plugin/plugin.json` | **modify** | Bump version to `0.3.0` |
| `.claude-plugin/marketplace.json` | **modify** | Bump version to `0.3.0` |

## Data Model Changes

**`.specclaw/config.yaml`** — adds:

```yaml
azdo:
  boards:
    sync: false               # default off
    work_item_type: "Feature"
    tag: "specclaw"
```

**`.specclaw/changes/<change>/status.md`** — gains a new line:

```
**Azure Boards Work Item:** [#1234](https://dev.azure.com/BistecGlobal/Agent-Accelerator/_workitems/edit/1234)
```

No schema changes elsewhere.

## API Changes

### New: `specclaw-azdo-issue`

```
specclaw-azdo-issue create   <specclaw_dir> <change>
specclaw-azdo-issue update   <specclaw_dir> <change>
specclaw-azdo-issue comment  <specclaw_dir> <change> "<comment text>"
specclaw-azdo-issue close    <specclaw_dir> <change>
```

Exit codes match the rest of specclaw:
- 0 — success
- 0 + warning to stderr — idempotent no-op (e.g. `create` when Work Item exists)
- 1 — failure (network, auth, config, ADO error)

### Modified: `specclaw-azdo-pr`

After successful PR creation, if `azdo.boards.sync: true` and `status.md` contains a Work Item ID, PATCH the Work Item to attach the PR via `ArtifactLink`. Failure to attach is a warning (not fatal — PR is already created).

## Key Decisions

**KD1 — Work item type defaults to `Feature`.** Per user. Override via `azdo.boards.work_item_type`.

**KD2 — No state transitions.** specclaw never touches `System.State`. ADO process templates vary too much (Agile / Scrum / Basic / custom) and the right transitions depend on team conventions. specclaw stays out of state machines. Humans drive state in ADO; specclaw provides description + comments + tags + a `closed-by-specclaw` tag on archive.

**KD3 — Auto-link PR via ArtifactLink relation.** The ADO REST relations API supports `ArtifactLink` of type `Pull Request` with a `vstfs://` URL encoding `projectId/repoId/prId`. This makes the PR show up under the Work Item's "Development" panel — the native ADO UX. Failure is non-fatal (PR is independently created and useful).

**KD4 — Reuse existing auth.** No new credential prompt. `/specclaw:auth-azdo` already saves the PAT, org, project. The new feature is opt-in via `azdo.boards.sync: true`, so users who already have ADO auth set up only need to flip a config flag.

**KD5 — Tag default `specclaw`.** Per user. Allows filtering (`tags: specclaw`) in ADO Boards queries.

**KD6 — Single-tag-by-default, comma-separated for multi.** ADO tags are comma-separated strings. The config value passes through verbatim.

**KD7 — Skill name `azdo-issue`, not `azdo-work-item`.** Parallels Jira's `/specclaw:issue` for ergonomic symmetry. Slightly imprecise (ADO calls them "Work Items", not "Issues") but matches user mental model from GitHub/Jira.

**KD8 — Minor version bump.** Additive feature, no behavior changes when disabled (default). v0.2.5 → v0.3.0 per semver.

**KD9 — Bash 3.2 + portable sed.** New script uses `sed_i` helper (from v0.2.5) for any in-place edits. No associative arrays.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Work item type not present in user's ADO process template | Medium | Surface the ADO 400 verbatim with the user's chosen type, suggest valid alternatives in the error message |
| ADO REST API rate limits | Low | Lifecycle calls are infrequent (1 per phase, not per task). Existing scripts also call ADO without issue. |
| ArtifactLink URL encoding bug (need project GUID, not name) | Medium | The PR script already knows `projectId` and `repoId` from creating the PR — pass those into the link payload directly. |
| User's ADO project uses different default `AreaPath` or `IterationPath` | Low | Don't specify these fields — let ADO use project defaults. If users need custom paths, that's a follow-up. |
| Description body is too large for ADO | Low | Truncate at 32K chars (well below ADO's 1M HTML field limit). Real proposals are <5K. |
| Multiple specclaw projects in same ADO project create tag collisions | Low | The default `specclaw` tag is acceptable for now; users can override per project via `azdo.boards.tag` |
| Idempotency check uses regex on status.md — fragile if status.md is edited by hand | Medium | Match strictly on `^\*\*Azure Boards Work Item:\*\* \[#` prefix. Users editing this line is their choice — treat as "no Work Item known" and try to create. |
