# specclaw-fleet

Runs an approved specclaw change headless in a sandboxed K3s Job, with `claude -p` or `codex exec`, on the **work-item assignee's own subscription**. The change's Azure Boards work item records each run. Optional add-on: core specclaw never needs it.

```
AzDO pipeline ── specclaw-fleet dispatch ──▶ Job (agent initContainer → writeback container)
   │                 gates · Key Vault             clone · plan/build/verify/pr-azdo · record state
   └── Boards work item ◀──────── Dispatched → Running → PR Open | Failed
```

## How credentials work

- Every person who can be assigned fleet work registers **their own** credential once:
  - Claude: the one-year token from `claude setup-token`. It authorizes model requests only, which is all a headless build needs.
  - Codex: a ChatGPT-plan `auth.json` from `codex login`. OpenAI's documented CI path.
- Credentials live in Azure Key Vault as `claude-token-<h>` and `codex-auth-<h>`. `<h>` is the first 16 hex characters of `sha256(lowercase UPN)`.
- **Per-secret RBAC:** each user holds `Key Vault Secrets Officer` on their own two secrets only, never on the vault.
- **At dispatch:** the assignee's secret is copied into a per-Job K8s Secret. That Secret is owned by the Job and garbage-collected with it.
- **No fallback, ever.** If the assignee has no credential registered, the run fails. Dispatch never uses anyone else's token.
- **Codex runs are limited to one at a time per person**, because one `auth.json` must never serve concurrent jobs. The person's codex Job has a fixed name, `fleet-codex-<h>`, so the Kubernetes API itself refuses a second one (`AlreadyExists`). A finished one is replaced by deleting it with a UID precondition, so a concurrent dispatch can never delete a newer run. After each run, the refreshed `auth.json` is written back to the vault, but only when it changed and still carries `tokens.refresh_token`. Claude runs have no such limit.
- **Cost:** each run spends the assignee's 5-hour and weekly plan allowance.

> **Security.** Code running in the pod can read the mounted token and the AzDO PAT. That includes code steered by prompt injection from repo content. The mitigations:
> - the egress allowlist;
> - the per-Job Secret is deleted with the Job;
> - the vault writer credential exists only in the write-back container. That container starts after the agent has exited, has its own empty HOME, mounts the codex directory read-only, calls `curl -q` so no `.curlrc` is read, and refuses an `auth.json` that is a symlink;
> - the writer service principal holds `Key Vault Secrets Officer` per secret, on each onboarded user's `codex-auth-<h>` only, never on the vault;
> - quick revoke and re-register (`specclaw-fleet login`).
>
> Rotate a token you suspect was exposed.

## Consent

Assigning a work item to someone must not spend their plan without their say. Dispatch runs only when one of these holds:
- the work item carries the tag `fleet:auto` (any case), and the work-item history shows that the assignee added it. A tag added by anyone else is not consent;
- the person who triggered the pipeline (`Build.RequestedForEmail`) is the assignee.

## Setup

1. **Cluster.** `kubectl apply -f k8s/`. This creates:
   - the namespace;
   - the dispatcher ServiceAccount and Role (Jobs: create/get/list/delete; Secrets: create only). It cannot read Secrets through the API. It can still create a Job that mounts one, so treat the dispatcher identity, meaning the pipeline and its service connection, as trusted;
   - the Squid egress proxy;
   - the NetworkPolicies.

   `specclaw-fleet` enforces Pod Security `restricted`, which fleet Jobs meet. Squid needs `SETUID`/`SETGID` to drop to its proxy user, so it runs in its own `specclaw-fleet-egress` namespace under `baseline`. That namespace holds no fleet Secrets. Pin `ubuntu/squid` by digest before production use.
2. **Secrets in the namespace.**
   - `fleet-azdo` holds `AZDO_TOKEN`, `AZDO_ORG` and `AZDO_PROJECT`. Use a PAT scoped to Code (read & write), Work Items (read & write) and Pull Request Threads.
   - `fleet-vault-writer` holds `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`, for a service principal. Do not grant it a vault-wide role. `onboard --writer <its object id>` grants it each user's `codex-auth-<h>` secret individually.
3. **Image.**
   ```bash
   docker build -f plugins/specclaw-fleet/image/Dockerfile \
     --build-arg CLAUDE_CODE_VERSION=<x.y.z> --build-arg CODEX_VERSION=<x.y.z> -t <registry>/specclaw-fleet:<tag> .
   ```
   Set `fleet.image` to that tag. On the first build, check that the `claude plugin install` and `codex plugin marketplace add` steps succeed; their syntax has not been tested against a live image yet.
4. **Onboard each user** (admin):
   ```bash
   specclaw-fleet onboard alice@contoso.com --vault <name> --writer <writer-sp-object-id>
   ```
   Then **each user** runs, themselves:
   ```bash
   specclaw-fleet login --agent claude --vault <name>
   specclaw-fleet login --agent codex  --vault <name>
   ```
5. **Boards (optional but recommended).** Add custom fields and states to your process, then map them in `.specclaw/config.yaml`. Without a mapping, every update still lands as a work-item comment.
   ```yaml
   azdo:
     fleet_fields:
       agent: Custom.FleetAgent
       job: Custom.FleetJob
       cluster: Custom.FleetCluster
       branch: Custom.FleetBranch
       exit: Custom.FleetExit
       attempt: Custom.FleetAttempt
       requested_by: Custom.FleetRequestedBy
       dispatched_commit: Custom.FleetDispatchedCommit
       built_commit: Custom.FleetBuiltCommit
     fleet_states:
       dispatched: Dispatched
       running: Running
       pr_open: PR Open
       failed: Failed
   fleet:
     vault: specclaw-fleet-kv
     vault_writer: <writer-sp-object-id>
     image: registry.example.com/specclaw-fleet:1
     default_agent: claude
     namespace: specclaw-fleet
     deadline_minutes: 120
   ```
6. **Pipeline.** Use `pipelines/dispatch.yml`. It runs on `main` when a change's `state.json` changes. It compares against the commit of the pipeline's last successful run, falling back to the parent commit on the first run, so an approval anywhere in a multi-commit push is seen. It dispatches only changes whose proposal became approved in that range. Any read failure fails the step. The pipeline agent needs `az`, `kubectl`, `jq`, `python3`, and `specclaw-fleet` plus `specclaw-azdo-issue` on `PATH`. Grant the build service identity read access to builds.

   **Which commit is built.** Dispatch records the commit that triggered it, and the pod checks that commit is an ancestor of the ref it clones before running. The agent builds on the ref's tip, so the base is fresh and still contains the approval. The work item records both commits.

## Egress hosts

The proxy allows CONNECT on port 443 to:
- `api.anthropic.com`, `downloads.claude.ai`
- `api.openai.com`, `auth.openai.com`, `chatgpt.com`, `*.chatgpt.com`
- `dev.azure.com`, `*.dev.azure.com`, `*.visualstudio.com`
- `login.microsoftonline.com`, `*.vault.azure.net`
- `registry.npmjs.org`

The full list of hosts Codex needs for its token refresh is not yet confirmed. Run one codex job, then check `kubectl -n specclaw-fleet-egress logs deploy/fleet-egress` for `TCP_DENIED` lines and add the hosts that are missing.

## Assumptions and known limits

- The org is backed by Entra ID, so a work item's `AssignedTo.uniqueName` equals the user's UPN. Guest or Microsoft-account users whose names differ just fail the credential check.
- **Deadlines.** The agent gets `fleet.deadline_minutes`. An in-pod watchdog stops it at that point and records `Failed`/`deadline`, then write-back still runs. The Job's own `activeDeadlineSeconds` is 10 minutes longer, as a backstop.
- **Clone failure.** A failed clone still marks the work item `Failed`, through a minimal tracker directory, as a comment and mapped fields only.
- **Hard kills.** A pod killed without SIGTERM (node loss, OOM) can leave the work item in `Running`. The Job status in the cluster is the source of truth. A reaper is a follow-up.
- **Vault errors.** A Key Vault read error at dispatch is reported as a vault problem, not as the assignee's missing credential. `onboard` writes a placeholder only when the secret is genuinely `NotFound`.
