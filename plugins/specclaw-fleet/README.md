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
- **Hosted (default):** a Microsoft-hosted agent (`pipelines/dispatch-hosted.yml`) fetches specclaw at a pinned ref and dispatches to a remote cluster over its API, using a least-privilege, short-lived dispatcher token. After each run on `main` or `feature/*` it also refreshes the committed `.specclaw/STATUS.md` (with `[skip ci]`). Change branches never write that file, so parallel members don't conflict on it; `/specclaw:status` on a change branch shows a local copy kept inside `.git`.
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
  cluster_name: bistec-dev-uat      # what the run record calls the cluster
  image: ghcr.io/chan4lk/specclaw-fleet:0.9.4
  claude_version: "2.1.319"         # required for claude jobs
  pipeline: specclaw-fleet
  pipeline_file: azure-pipelines/specclaw-fleet.yml   # doctor reads the connection names from it
```

- **Which cluster your machine talks to is local, not shared:** set `FLEET_KUBE_CONTEXT` and `KUBECONFIG` in the gitignored `.specclaw/.env`. A relative `KUBECONFIG` resolves against the repo root. They are never read from `fleet:`, and the pipeline always uses the kubeconfig its Kubernetes task logged in.
- **Other keys:** `namespace`, `default_agent`, `deadline_minutes`, `remote`, `ref`, `image_pull_secret` (private registries only), and `node_label` (`key=value`, which pins Jobs to a labelled, tainted node).
- **Postgres for tests:** set `postgres_image` (pinned by digest, e.g. `postgres:16@sha256:…`; use a Debian-based tag, because the pod runs as uid 1000) to give each Job a Postgres sidecar on `127.0.0.1`. It starts before the agent, is ready when `pg_isready` passes, and stops with the Job. Optional: `postgres_port` (default `5432`), `postgres_user`, `postgres_password`, `postgres_db` (default `postgres`; letters, digits, `_` and `-` only). The agent gets `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`. The values are a throwaway test database, never a real credential.
- **Playwright:** the image ships browsers for its own Playwright version (`PLAYWRIGHT_VERSION` in `image/Dockerfile`) in a read-only path, and the Playwright CDN is not on the egress allowlist. A repo's `@playwright/test` must match that version, or its browser tests cannot run in the pod.
- **Several Azure DevOps projects, one namespace:** the pod takes `AZDO_ORG` and `AZDO_PROJECT` from the repo URL it cloned (`https://dev.azure.com/<org>/<project>/_git/<repo>`, or the legacy `https://<org>.visualstudio.com/<project>/_git/<repo>`), overriding the `fleet-azdo` secret, so one namespace serves repos in any project of the org. The secret's PAT must reach every project it serves.
- **Security settings** (`vault`, `image`, `postgres_image`, `namespace`, `node_label`, `image_pull_secret`, `claude_version`, `deadline_minutes`, `cluster_name`) are read in pipeline runs only from the trusted branch (`fleetTrustedBranch`, default `main`). A run on a branch whose values differ stops before dispatch. The pipeline YAML itself is branch-controlled, so this check is defence in depth: **the real guard is an AzDO Branch control check on both service connections**, allowing only `refs/heads/main` (plus protected `refs/heads/feature/*` if you use coordinated features).
- **Connection names** live only in the pipeline YAML (AzDO needs them at compile time). `doctor` reads them from `pipeline_file`.
- **Precedence:** a flag, then an env variable (`FLEET_<KEY>`), then config, then the default.
- **Secrets never go here.** The PAT stays in the gitignored `.specclaw/.env`, and a secret-looking value is refused.

## Running a change

Run **`/specclaw-fleet:run <change>...`**. It opts the changes in, triggers them in parallel, and watches each one until it has a PR or a recorded failure. The commands it uses:

```bash
specclaw-fleet optin 002-catalog 003-detail      # assign to you + fleet:auto, as you (never anyone else)
specclaw-fleet trigger 002-catalog [--create] [--retry] [--direct]
specclaw-fleet status --watch                    # one line per change: item, tags, last record, Job
```

`optin` uses the identity behind `AZDO_TOKEN`. It refuses an item assigned to someone else, and `--dry-run` shows the plan without writing. `status` is read-only. A change shows `not-opted-in` until `fleet:auto` is added by its assignee, and `did-not-run` when the run `trigger` queued for it (`--run <change>=<id>`) finished without dispatching it. `--watch` ends when every change has ended, or after `--timeout` minutes (exit 2).

`trigger` reads approval from the **pushed** ref (`FLEET_REMOTE`/`FLEET_REF`, default `origin/main`). It refuses an unapproved proposal, a work item with no assignee, missing `fleet:auto` consent from the assignee, or a missing credential. Refusals have no side effects. `--create` is the one deliberate exception: it creates the missing work item and stops (exit 3), so the item can be assigned and consented.

Once the gates pass, `trigger` queues the pipeline with this change and agent as runtime parameters, or dispatches directly with `--direct`. `--retry` clears `fleet:dispatched` and `fleet:refused` first.

## Coordinated features

Run **`/specclaw-fleet:feature`** to deliver related changes together. Children declare `**Feature:** <module>` and `**Depends on:** <changes>` in their proposal (or lean `change.md`). `feature plan` shows waves and states; `feature init` writes `.specclaw/features/<module>/` with its own work item; `feature start` creates `feature/<module>` and queues the pipeline, which then runs `feature advance` on every merge into that branch that changes a `.specclaw/changes/*/state.json` (every child PR does; after any other merge, run `feature start <module>` again to re-queue it): ready children dispatch on `feature/<module>` (their PRs target it), a failed child blocks only its dependents, a conflicting child is retried once with the feature branch merged in, and once every child is merged one integration run opens `specclaw/integrate-<module> → <trusted branch>`.

## Build report and pane

`specclaw-fleet report` shows how a build went. Every run record now carries:
- `pipeline_run`;
- the agent's start, end and seconds;
- cost, turns and model, from Claude's JSON result;
- review rounds;
- the commits the agent made.

So the report outlives pods and the 4,000-byte log tail.

```bash
specclaw-fleet report                       # latest build: table + totals
specclaw-fleet report --feature catalog     # one feature, by wave
specclaw-fleet report --save                # write .specclaw/fleet/report.json for the pane
specclaw-fleet report --html build.html     # one self-contained page, no network
specclaw-fleet report --json                # the snapshot document
```

The report only reads: records first, then AzDO PRs and pipeline runs, then the cluster for runs still going. A failed read blanks a field and never fails the report. Cost is an API-equivalent estimate.

**The mod (Claude Code).** The plugin ships a mod that reads only the saved snapshot. It adds:
- **`/fleet-pane`:** a pane beside the chat with the timeline (`░` pipeline, `█` agent, `▒` PR open), the lifecycle table and the totals.
- **A band above the prompt:** `fleet · 2 running · 4 PRs open · last run 13:51 UTC`.
- **A status line:** `fleet: 2 running`.

It re-reads the snapshot after any `specclaw-fleet trigger`, `status` or `report` Bash call; only `report --save` writes a new one. It never runs commands or calls the network itself. `/specclaw-fleet:report` runs the report and points you at the pane.

## Hosted minutes

Fleet runs on Microsoft-hosted agents by default. A private project gets **1 free hosted parallel job and 1,800 minutes a month**; user licences (Basic access) do not add parallel jobs.

The hosted job only dispatches: the Claude or Codex work runs in pods on your cluster and uses no hosted minutes. A dispatch run takes about 45 seconds (a sparse checkout of `.specclaw/`, a blob-less fetch of the two fleet plugins, kubectl login, dispatch), and every run stops at `timeoutInMinutes: 10`. So the free grant covers well over a thousand dispatch or `feature advance` runs a month.

Check usage under **Organization settings → Parallel jobs**. If runs start queueing or minutes run out, buy a hosted parallel job, or enable a self-hosted overflow agent (deferred in change 051; the org has one free self-hosted job).

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
