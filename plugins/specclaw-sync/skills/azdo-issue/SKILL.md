---
description: Use when a change should be mirrored as an Azure Boards work item.
---

# specclaw azdo-issue

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create an Azure Boards Work Item from a specclaw change. Requires:
- `proposal.md` to exist (run `/specclaw:propose` first).
- `azdo.boards.sync: true` and a valid `azdo.boards.work_item_type` in `config.yaml`.
- ADO credentials already set up via `/specclaw-sync:auth-azdo`.

## Subcommands

**Create the Work Item:**
```bash
specclaw-azdo-issue create .specclaw <change>
```
Idempotent — if a Work Item already exists for this change (recorded in `status.md`), exits with a warning and does not duplicate.

**Update the Work Item description with the latest task checklist:**
```bash
specclaw-azdo-issue update .specclaw <change>
```

**Post a comment:**
```bash
specclaw-azdo-issue comment .specclaw <change> "<comment text>"
```

**Close (final comment + closed-by-specclaw tag, no state transition):**
```bash
specclaw-azdo-issue close .specclaw <change>
```

**Link a pull request to the Work Item:**
```bash
specclaw-azdo-issue link-pr .specclaw <change> <project_id> <repo_id> <pr_id>
```
Called automatically by `/specclaw-sync:pr-azdo`; rarely invoked directly.

**Print the Work Item JSON, or its revision history:**
```bash
specclaw-azdo-issue show .specclaw <change>
specclaw-azdo-issue updates .specclaw <change>
```
`updates` pages through the whole history (200 at a time) and fails rather than return a partial one.

**Add a tag (idempotent, case-insensitive):**
```bash
specclaw-azdo-issue tag .specclaw <change> fleet:dispatched
```

**Claim atomically / remove a tag:**
```bash
specclaw-azdo-issue claim .specclaw <change> fleet:dispatched fleet:refused
specclaw-azdo-issue untag .specclaw <change> fleet:dispatched
```
`claim` exits 3 when the work item already holds the tag or any blocking tag, or when another writer changed it in between. Its PATCH carries a `test /rev` precondition, so two claimants can never both win.

**Record run fields (used by specclaw-fleet):**
```bash
specclaw-azdo-issue fields .specclaw <change> agent=codex job=fleet-049-ab12c state=running
```
Each `key` is written only when `azdo.fleet_fields.<key>` names an AzDO field reference (e.g. `Custom.FleetAgent`); `state=<value>` sets `System.State` only when `azdo.fleet_states.<value>` names a state in your process. Unmapped keys are skipped with a warning, so an unmodified process template never gets a PATCH that fails. Every call also posts one comment listing all pairs, which is the run record when no custom fields exist.

## Notes

- Core specclaw does **not** transition Work Item state; only `fields` does, and only to states you map in `azdo.fleet_states`. Auto-transitioning is too easy to break across ADO process templates (Agile / Scrum / Basic). Humans drive state in ADO; specclaw only writes description, comments, and tags.
- The Work Item is tagged with `azdo.boards.tag` (default `specclaw`) so you can filter specclaw items in Boards queries.
- On archive, an additional `closed-by-specclaw` tag is added so completed changes are easy to find.
- After creation, the Work Item ID and URL are saved to `.specclaw/changes/<change>/status.md` as `**Azure Boards Work Item:** [#1234](url)` — this line is also used for idempotency checks on subsequent runs.
