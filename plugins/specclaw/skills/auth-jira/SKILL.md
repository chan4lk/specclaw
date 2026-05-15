---
description: Interactive setup for Jira authentication. Prompts for domain, email, project key, and issue type, validates an Atlassian API token, and saves credentials. Run once per project before /specclaw:issue.
disable-model-invocation: true
---

# specclaw auth jira

Interactive Jira authentication setup. Guides the user to create an Atlassian API token, validates it, and saves credentials.

1. **Run:** `specclaw-auth-jira .specclaw`
   - Prompts for domain (e.g. `mycompany.atlassian.net`), email, project key, issue type.
   - Guides the user to `https://id.atlassian.com/manage-profile/security/api-tokens`.
   - Validates credentials and project key via Jira REST API.
   - Saves domain/email/project_key/issue_type to `config.yaml` under the `jira:` section; token to `.specclaw/.env` (gitignored).
2. Report success and suggest `/specclaw:issue <change>` as the next step.
