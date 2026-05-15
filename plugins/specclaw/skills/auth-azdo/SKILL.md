---
description: Interactive setup for Azure DevOps authentication. Prompts for organization, project, and repo, validates a Personal Access Token, and saves credentials to gitignored .specclaw/.env. Run once per project before /specclaw:pr-azdo.
disable-model-invocation: true
---

# specclaw auth azdo

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Interactive Azure DevOps authentication setup. Guides the user to create a PAT, validates it, and saves credentials.

1. **Run:** `specclaw-auth-azdo .specclaw`
   - Prompts for org name, project name, repo name.
   - Guides the user to `https://dev.azure.com/<org>/_usersSettings/tokens` to create a PAT.
   - Required scopes: Code (Read & Write), Work Items (Read & Write).
   - Validates the token via ADO REST API.
   - Saves org/project/repo to `config.yaml` under the `azdo:` section; token to `.specclaw/.env` (gitignored).
2. Report success and suggest `/specclaw:pr-azdo <change>` as the next step.
