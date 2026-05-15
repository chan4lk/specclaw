---
description: Create a Jira issue for a proposed change. Mirrors GitHub Issues sync but for Jira-based teams. Builds the issue summary and description from proposal.md and spec.md. Requires credentials from /specclaw:auth-jira. Idempotent — warns if a Jira issue already exists for this change.
disable-model-invocation: true
---

# specclaw issue

Create a Jira issue from a specclaw proposal. Requires `proposal.md` (run `/specclaw:propose` first).

1. **Check idempotency:** if `status.md` already records a Jira issue for this change, warn and skip.
2. **Run:** `specclaw-jira-issue .specclaw <change>`
   - Requires `JIRA_TOKEN`, `JIRA_URL`, `JIRA_EMAIL`, `JIRA_PROJECT` (set via `/specclaw:auth-jira`).
   - Builds summary (≤255 chars) from the first non-header line of `proposal.md`.
   - Builds description (ADF format) from `proposal.md` + `spec.md` (if present).
   - Creates the issue via Jira REST API v3.
   - **Saves:** appends `**Jira Issue:** [KEY](url)` to `status.md`.
3. Report the Jira issue key and URL to the user.
