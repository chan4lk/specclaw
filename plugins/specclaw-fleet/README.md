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

Assigning a work item to someone must not spend their plan without their say. Dispatch runs only when the work item carries the tag `fleet:auto` (any case), and the full work-item history shows that the assignee is the one who added it.
- A tag added by anyone else is not consent.
- Triggering the pipeline is not consent either, because a run scans every pending change, not only the one you pushed.

## Setup

Run **`/specclaw-fleet:setup`**. It works until `specclaw-fleet doctor` is clean, asks before every outward-facing action, and hands every credential step to you in a real terminal.

`specclaw-fleet doctor` is read-only. It prints one `ok`/`missing`/`wrong`/`skip` line per item, then exits 0 only when nothing needs attention. It covers:
- the kube context, namespaces, RBAC, proxy and NetworkPolicy;
- both cluster secrets (by key names only);
- the Key Vault and the GHCR image;
- the AzDO pipeline and its service connections.

**Modes**
- **Hosted (default):** a Microsoft-hosted agent (`pipelines/dispatch-hosted.yml`) fetches specclaw at a pinned ref and dispatches to a remote cluster over its API, using a least-privilege, short-lived dispatcher token.
- **Local:** a self-hosted agent (`pipelines/dispatch.yml`) installed as a service.

**Image:** a public GHCR image built for amd64 and arm64 by `.github/workflows/fleet-image.yml`.
- It contains **no Claude Code binary**.
- Each pod downloads `FLEET_CLAUDE_VERSION` from `downloads.claude.ai`, checks the manifest's GPG signature against Anthropic's pinned key (`31DD…CACE`), then the SHA256 and size.
- It records the download time as `claude_fetch_s`.
- `DISABLE_UPDATES=1` keeps it on that version.

**Settings** live in the `fleet:` block of `.specclaw/config.yaml`, so no command needs an env prefix:

```yaml
fleet:
  vault: kv-scfleet-965892
  kube_context: bistec-dev-uat      # local commands only; the pipeline uses its logged-in kubeconfig
  cluster_name: bistec-dev-uat      # what the run record calls the cluster
  image: ghcr.io/chan4lk/specclaw-fleet:0.9.0
  claude_version: "2.1.319"         # required for claude jobs
  pipeline: specclaw-fleet
  kube_connection: specclaw-fleet-hetzner
  azure_connection: specclaw-fleet-azure
```

- **Other keys:** `kubeconfig`, `namespace`, `default_agent`, `deadline_minutes`, `remote`, `ref`, `image_pull_secret` (private registries only), and `node_label` (`key=value`, which pins Jobs to a labelled, tainted node).
- **Precedence:** a flag, then an env variable (`FLEET_<KEY>`, or `KUBECONFIG` for `kubeconfig`), then config, then the default.
- **Secrets never go here.** The PAT stays in the gitignored `.specclaw/.env`, and a secret-looking value is refused.

## Running a change

Run **`/specclaw-fleet:run <change>...`**. It opts the changes in, triggers them in parallel, and watches each one until it has a PR or a recorded failure. The commands it uses:

```bash
specclaw-fleet optin 002-catalog 003-detail      # assign to you + fleet:auto, as you (never anyone else)
specclaw-fleet trigger 002-catalog [--create] [--retry] [--direct]
specclaw-fleet status --watch                    # one line per change: item, tags, last record, Job
```

`optin` uses the identity behind `AZDO_TOKEN`. It refuses an item assigned to someone else, and `--dry-run` shows the plan without writing. `status` is read-only. A change shows `not-opted-in` until `fleet:auto` is added by its assignee.

`trigger` reads approval from the **pushed** ref (`FLEET_REMOTE`/`FLEET_REF`, default `origin/main`). It refuses an unapproved proposal, a work item with no assignee, missing `fleet:auto` consent from the assignee, or a missing credential. Refusals have no side effects. `--create` is the one deliberate exception: it creates the missing work item and stops (exit 3), so the item can be assigned and consented.

Once the gates pass, `trigger` queues the pipeline with this change and agent as runtime parameters, or dispatches directly with `--direct`. `--retry` clears `fleet:dispatched` and `fleet:refused` first.

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
- **Deadlines.** The agent gets `FLEET_DEADLINE_MINUTES`. An in-pod watchdog stops it at that point and records `Failed`/`deadline`, then write-back still runs. The Job's own `activeDeadlineSeconds` is 10 minutes longer, as a backstop.
- **Clone failure.** A failed clone still marks the work item `Failed`, through a minimal tracker directory, as a comment and mapped fields only.
- **Hard kills.** A pod killed without SIGTERM (node loss, OOM) can leave the work item in `Running`. The Job status in the cluster is the source of truth. A reaper is a follow-up.
- **Vault errors.** A Key Vault read error at dispatch is reported as a vault problem, not as the assignee's missing credential. `onboard` writes a placeholder only when the secret is genuinely `NotFound`.
