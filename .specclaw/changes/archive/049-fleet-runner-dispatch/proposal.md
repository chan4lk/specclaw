# Proposal: specclaw-fleet — sandboxed K3s jobs running Claude or Codex on the assignee's own plan

**Created:** 2026-11-07
**Status:** ✅ Approved

## Problem

Today a specclaw change is built in whatever terminal the operator has open. You cannot hand an approved proposal to sandboxed infrastructure and leave. You also cannot see from Azure DevOps which proposals are running, where they are running, or how they ended.

Anthropic's self-hosted environments were considered and rejected. Starting a session there needs a claude.ai OAuth login renewed every 30 days, and one automation seat would carry every run's usage. That breaks against per-seat 5-hour and weekly limits. A shared pool of rotated seats is not an option either.

Both CLIs can run headless in our own container on a subscription credential:
- **Claude:** `claude -p` with a `claude setup-token` token (one year, model requests only).
- **Codex:** `codex exec` with a ChatGPT-plan `auth.json`. This is OpenAI's documented CI path, and Codex refreshes the file roughly every 8 days.

If each run uses the credentials of the person the work item is assigned to, usage lands on that person's own seat. That keeps us honest under each vendor's terms and spreads load naturally.

This is optional infrastructure that most specclaw users will never run, so it must not land in the core plugin.

## Proposed Solution

Add a new plugin, **`plugins/specclaw-fleet/`**, installed on its own. This change is the first of three; 050 and 051 build on it.

1. **One K8s Job per change run, on K3s.** The pod is the sandbox.
   - **Image:** `claude`, `codex`, git, jq and the specclaw plugins (Claude plugin and Codex packaging) installed, with no secrets in the image.
   - **Network:** a default-deny `NetworkPolicy`. Egress goes through an allowlisting proxy: `api.anthropic.com`, `api.openai.com` / `chatgpt.com` auth endpoints, `dev.azure.com`, `*.visualstudio.com`, and the package mirror. `169.254.169.254` is blocked.
   - **Pod settings:** non-root user, read-only root filesystem except the workspace, and `activeDeadlineSeconds` as a hard cap on run time.
   - **Permissions:** the pod is the sandbox, so the agent runs without per-tool prompts. That is `--dangerously-skip-permissions` for Claude, and `codex exec` with full auto in the workspace for Codex.
2. **The agent is chosen per run.** `--agent claude|codex` is passed on the command line, or comes from a work-item field. The default comes from config.
3. **Per-assignee credentials in Azure Key Vault**, keyed by the assignee's AzDO identity (`claude-token-<id>`, `codex-auth-<id>`).
   - **Registration:** `specclaw-fleet login --agent claude|codex` runs `claude setup-token` or `codex login` locally under the user's own account. It uploads the result with the user's own Azure identity, so no admin ever handles anyone's token.
   - **At dispatch:**
     - read `System.AssignedTo` from the work item;
     - fetch that person's secret;
     - create a per-Job K8s Secret with an `ownerReference` to the Job, so it is deleted with the Job;
     - mount it only into the agent container.
   - **Codex write-back:** after the run, the job writes `auth.json` back to Key Vault only if it changed. Codex runs are **serialized per assignee**, because OpenAI says one `auth.json` must never serve concurrent jobs. Dispatch refuses a second Codex run for a user who already has one `Running`.
   - **Missing or expired credential:** the work item goes to `Failed` with "assignee has no registered <agent> credential — run `specclaw-fleet login`". No other person's token is ever used as a fallback.
4. **Consent gate.** Assigning a work item to someone must not spend their plan. Dispatch requires that the assignee opted in, through a `fleet:auto` tag they set or by being the one who triggered the run. It also requires that the change is `proposal approved`.
5. **`specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>]`.**
   - Renders the Job, then applies it with `kubectl` through a namespace-scoped ServiceAccount that can only create Jobs and Secrets in the fleet namespace.
   - The in-pod entrypoint clones over HTTPS with a short-lived AzDO token, then runs plan → build → verify → `pr-azdo` headless. It pushes the branch and reports the exit status.
   - Before calling the CLI, the entrypoint unsets `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `CODEX_API_KEY`, so a stray API key can never override the subscription credential.
6. **The work item is the run record.** Through `specclaw-azdo-issue`, it carries:
   - Agent, Job name, Cluster, Branch, Exit status, Attempt and Requested by (`Build.RequestedFor`);
   - state `Dispatched → Running → PR Open → Done | Failed`.

   Dispatch and the in-pod entrypoint each write their own transition. The PR stays linked, as today.
7. **AzDO pipeline template** that runs `dispatch` when a merge to `main` adds an approved `proposal.md`.

## Scope

### In Scope
- New `plugins/specclaw-fleet/` with `.claude-plugin/plugin.json` at the shared version, and a new entry in `.claude-plugin/marketplace.json`.
- The image Dockerfile, the in-pod entrypoint, and the K8s manifests: namespace, ServiceAccount/Role, Job template, NetworkPolicy, egress proxy config.
- `bin/specclaw-fleet dispatch` and `bin/specclaw-fleet login`, skills wrapping them, and tests that stub `kubectl`, `az`, `claude`, `codex` and the AzDO REST calls. The tests cover:
  - assignee lookup;
  - the consent gate;
  - refusing to fall back to another person's credential;
  - Codex per-user serialization;
  - Codex write-back only on change;
  - unsetting the API-key variables.
- An `update` option on `specclaw-azdo-issue` (specclaw-sync) that writes the new fields and state, and is a no-op when a field is missing from the process. This is the only edit outside the new plugin.
- `docs/` setup guide covering:
  - the Key Vault layout and RBAC;
  - the AzDO custom fields and states;
  - credential registration and rotation (the setup token expires after one year, and a Codex refresh failure needs a fresh `codex login`);
  - the consent tag;
  - a cost note: each run spends the assignee's 5-hour and weekly plan allowance.

### Out of Scope
- Any change to the core `plugins/specclaw/`.
- Anthropic self-hosted environments, `--environment` / `--cloud` dispatch, and the claude.ai session view.
- Shared, pooled or rotated automation accounts.
- API-key (per-token) billing and third-party model gateways (DeepSeek, Qwen). A possible later change.
- Starting several proposals as one feature, integration branches, waves, fan-in (change 050).
- Self-hosted Azure Pipelines agents and minute-saving pipeline patterns (change 051).

## Impact

- **Size:** architectural. It adds a new plugin plus the dispatch and credential interfaces that 050 and 051 depend on.
- **Files affected:** ~18 (estimated)
- **Complexity:** large
- **Risk:** high. The job handles people's personal subscription tokens.
  - Code running in the pod, including through prompt injection from repo content, can read the mounted token. A Claude setup token stays valid for one year.
  - Mitigations: egress allowlist, per-Job Secret deleted with the Job, token mounted only into the agent container, one-click revoke and re-register.

## Open Questions

- Plugin name: `specclaw-fleet`, or something else?
- **Decided (2026-11-07):** Key Vault RBAC is restricted per user. Each user gets `Key Vault Secrets Officer` scoped to their own `claude-token-<id>` / `codex-auth-<id>` secrets only, assigned at onboarding. No vault-wide write.
- **Decided (2026-11-07):** Claude runs are not serialized; one setup token may serve concurrent jobs. Revisit only if Anthropic says otherwise.
- Consent model: is a `fleet:auto` tag enough, or should each dispatch need the assignee's explicit approval (an AzDO approval check)?
- AzDO token for cloning: workload identity federation (preferred) or a scoped PAT in a K8s secret as the first version?
- Egress allowlist: a Squid proxy (works on stock K3s), or require Cilium FQDN policies? Which exact OpenAI hosts does Codex need for its token refresh? (Unknown, so build captures them from proxy logs in a test run.)
- A pod that is killed outright never reports. Do we need a reaper that marks stale `Running` items as `Failed`?
