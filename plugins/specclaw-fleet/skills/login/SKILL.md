---
description: Use when a person needs to register or refresh their own Claude or Codex subscription credential for specclaw-fleet runs.
---

# specclaw-fleet login

Stores the caller's own credential in Azure Key Vault so fleet jobs assigned to them can run on their plan. The user runs this themselves; never run it for someone else, and never ask them to paste a token into chat.

```bash
specclaw-fleet login --agent claude --vault <name>
specclaw-fleet login --agent codex  --vault <name>
```

- **claude** runs `claude setup-token` in the terminal, then asks the user to paste the printed token at a hidden prompt.
- **codex** runs `codex login` into a temporary `CODEX_HOME` with file credential storage and uploads the resulting `auth.json`.

The secret name comes from a hash of the user's own `az` identity, and per-secret RBAC (granted once by an admin with `specclaw-fleet onboard <upn> --vault <name>`) lets each person write only their own two secrets.

Re-run it when the Claude setup token nears its one-year expiry, or after a codex job reports a failed token refresh.
