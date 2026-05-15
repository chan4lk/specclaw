---
description: Create an Azure DevOps pull request for a verified change. Mirrors /specclaw:pr but targets ADO Repos via REST API instead of GitHub. Requires credentials from /specclaw:auth-azdo. Use when the project uses Azure DevOps instead of GitHub.
---

# specclaw pr-azdo

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create an Azure DevOps PR for a verified change.

1. **Validate:** `specclaw-validate-change .specclaw <change> pr`. Fails if `verify-report.md` is missing.
2. **Run:** `specclaw-azdo-pr .specclaw <change>`
   - Requires `AZDO_TOKEN`, `AZDO_ORG`, `AZDO_PROJECT`, `AZDO_REPO` (set via `/specclaw:auth-azdo`).
   - **Test policy:** same gate as `/specclaw:pr` — prompts once, enforces on all runs.
   - **PR creation:** builds title (≤128 chars) from `proposal.md`, description from `spec.md` + `verify-report.md`, calls ADO REST API.
   - **Saves URL:** appends `**ADO PR:** <url>` to `status.md`.
3. Report the ADO PR URL to the user.
