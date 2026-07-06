---
description: "Create or update an Azure Boards Work Item that mirrors this proposal. Targets Azure DevOps Boards (Features / User Stories / Tasks / Bugs / Epics) using the credentials from /specclaw:auth-azdo. Mirrors /specclaw:issue (Jira) and the GitHub Issues sync but for ADO Boards. Requires `azdo.boards.sync: true` in config.yaml."
---

# specclaw azdo-issue

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create an Azure Boards Work Item from a specclaw change. Requires:
- `proposal.md` to exist (run `/specclaw:propose` first).
- `azdo.boards.sync: true` and a valid `azdo.boards.work_item_type` in `config.yaml`.
- ADO credentials already set up via `/specclaw:auth-azdo`.

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
Called automatically by `/specclaw:pr-azdo`; rarely invoked directly.

## Notes

- specclaw does **not** transition Work Item state. Auto-transitioning is too easy to break across ADO process templates (Agile / Scrum / Basic). Humans drive state in ADO; specclaw only writes description, comments, and tags.
- The Work Item is tagged with `azdo.boards.tag` (default `specclaw`) so you can filter specclaw items in Boards queries.
- On archive, an additional `closed-by-specclaw` tag is added so completed changes are easy to find.
- After creation, the Work Item ID and URL are saved to `.specclaw/changes/<change>/status.md` as `**Azure Boards Work Item:** [#1234](url)` — this line is also used for idempotency checks on subsequent runs.
