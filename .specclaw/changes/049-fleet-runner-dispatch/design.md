# Design: specclaw-fleet — sandboxed K3s jobs running Claude or Codex on the assignee's own plan

**Change:** 049-fleet-runner-dispatch
**Created:** 2026-11-07

## Technical Approach

The plugin is one Bash entry point, `bin/specclaw-fleet`, with three subcommands:
- `onboard`: an admin gives a user their own two vault secrets.
- `login`: a user stores their own token.
- `dispatch`: launches one run.

The Job YAML is generated inside `dispatch` from a heredoc, not from a template file, so tests assert on the exact manifest that gets applied. Everything outside the pod is derived from live sources and nothing is cached. A user's credential exists in exactly two places: the vault and a per-Job K8s Secret.

```
AzDO pipeline (az + kubectl)                      K3s namespace specclaw-fleet
───────────────────────────                      ──────────────────────────────────────────
specclaw-fleet dispatch <change>                  Job fleet-<nnn>-<rand>
  gates: approved · WI · assignee · consent        initContainer  agent   (entrypoint.sh)
         · credential · codex-serial                 env CLAUDE_CODE_OAUTH_TOKEN | CODEX_HOME seed
  az keyvault secret show <agent>-…-<h>              clone → Running → claude -p | codex exec
  kubectl create Job, then Secret (ownerRef=Job)     → PR Open | Failed → /status/exit
                                                   container      writeback (writeback.sh)
  azdo-issue fields … state=dispatched               codex: hash changed? → PUT vault secret
                                                     exit $(cat /status/exit)
                                                   egress → squid (allowlist) only
```

## Architecture

- **Two containers, run one after the other.** The agent runs as an **initContainer**, so it finishes before the main container starts. Write-back runs as the **main container**.
  - The vault service-principal secret is mounted into `writeback` only.
  - The pod sets `automountServiceAccountToken: false`, so the agent container holds no cluster or vault credential.
  - The agent step always exits 0 and records its real status in a shared emptyDir. That lets write-back run after a failure, and the Job still ends with the true status.
- **Codex concurrency comes from the cluster.** `kubectl get jobs -l specclaw.fleet/agent=codex,specclaw.fleet/assignee=<h> -o json`, filtered with jq to Jobs that have neither `succeeded` nor `failed`. No state file, so it follows "derived, not stored".
- **Consent:** dispatch proceeds when the work item has the tag `fleet:auto` (exact match in `System.Tags`, split on `; `), or when the requester's email `$BUILD_REQUESTEDFOREMAIL` equals the assignee's `uniqueName`, compared case-insensitively.
- **Work-item writes go through `specclaw-azdo-issue fields`.** One writer for Boards stays in specclaw-sync. The fleet calls it by bare name, with the usual PATH fallback to `../../specclaw-sync/bin`.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw-fleet/.claude-plugin/plugin.json` | create | Claude manifest at the shared version |
| `plugins/specclaw-fleet/.codex-plugin/plugin.json` | create | Codex manifest, `"skills": "./skills/"` |
| `.claude-plugin/marketplace.json` | modify | add the `specclaw-fleet` entry |
| `.agents/plugins/marketplace.json` | modify | add the `specclaw-fleet` entry |
| `plugins/specclaw/tests/run-codex-plugin-tests.sh` | modify | add the new name to the inventory assertion (line 46) |
| `plugins/specclaw-fleet/bin/specclaw-fleet` | create | router; sources `lib/*.sh` |
| `plugins/specclaw-fleet/lib/{common,vault,workitem,naming,manifest,dispatch,launch}.sh` | create | split to keep every file ≤ 80 lines (base preset): helpers, onboard/login, Boards + gates, safe names, Secret/Job render, dispatch flow, create + record |
| `plugins/specclaw-fleet/image/Dockerfile` | create | debian-slim with git, jq, curl, python3, `claude`, `codex`, specclaw plugins baked in; non-root `agent` user |
| `plugins/specclaw-fleet/image/entrypoint.sh` | create | agent step (FR-6) |
| `plugins/specclaw-fleet/image/writeback.sh` | create | write-back step (FR-7), vault REST over curl |
| `plugins/specclaw-fleet/k8s/namespace.yaml` | create | namespace |
| `plugins/specclaw-fleet/k8s/rbac.yaml` | create | dispatcher ServiceAccount, Role, RoleBinding |
| `plugins/specclaw-fleet/k8s/egress-proxy.yaml` | create | Squid Deployment, Service, allowlist ConfigMap |
| `plugins/specclaw-fleet/k8s/network-policy.yaml` | create | default-deny fleet pods; proxy egress 443 minus private/metadata ranges |
| `plugins/specclaw-fleet/pipelines/dispatch.yml` | create | AzDO pipeline template (FR-10) |
| `plugins/specclaw-fleet/skills/dispatch/SKILL.md` | create | when and how to dispatch |
| `plugins/specclaw-fleet/skills/login/SKILL.md` | create | per-user credential registration |
| `plugins/specclaw-fleet/README.md` | create | setup guide: vault RBAC, fields and states, PAT scope, proxy hosts, consent, cost note |
| `plugins/specclaw-fleet/tests/run-fleet-tests.sh` | create | runs every `tests/cases/*.sh` |
| `plugins/specclaw-fleet/tests/lib/{harness,dispatch-env}.sh`, `tests/cases/ac{2,3,4,5,6,7,8,10}_*.sh` | create | stubs and one case file per AC group |
| `plugins/specclaw-sync/bin/specclaw-azdo-issue` | modify | new `fields` subcommand |
| `plugins/specclaw-sync/skills/azdo-issue/SKILL.md` | modify | document `fields` |
| `plugins/specclaw-sync/tests/run-azdo-issue-fields-tests.sh` | create | AC-9 |
| `.github/workflows/ci.yml` | modify | register both new suites |

## Data Model Changes

Config keys, all optional:
- `fleet.default_agent`
- `fleet.namespace` (default `specclaw-fleet`)
- `fleet.image`
- `fleet.deadline_minutes` (default 120)
- `fleet.vault`
- `azdo.fleet_fields.{agent,job,cluster,branch,exit,attempt,requested_by}`: AzDO field reference names
- `azdo.fleet_states.{dispatched,running,pr_open,failed}`: AzDO state names

Vault secrets: `claude-token-<h>` and `codex-auth-<h>`, with placeholder value `__unset__`.

## API Changes

- `specclaw-fleet onboard <upn> --vault <v>`
- `specclaw-fleet login --agent claude|codex --vault <v>`
- `specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <b>] [--vault <v>] [--dry-run]`
  - `--dry-run` prints the manifests with the secret redacted and applies nothing. It is used by the tests and by operators.
- `specclaw-azdo-issue fields <dir> <change> key=value…`

## Key Decisions

- **Agent first, write-back second.** A native sidecar would run alongside the agent and hold the vault credential the whole time. Running the agent as an initContainer and write-back as the main container means the credential exists only after the agent has stopped.
- **Hash of the UPN, not the Entra object ID.** Dispatch needs no Graph permission. The edge case where AssignedTo differs from the UPN is covered by A1 and documented.
- **Fields go only to mapped keys, plus an audit comment.** An AzDO PATCH that names a missing field fails the whole request. Mapping-only writes keep the fleet working on an unmodified process template.
- **Squid over Cilium.** It works on stock K3s (flannel plus the built-in policy controller), and the NetworkPolicy reduces egress to "DNS plus proxy".
- **Job first, then an owned Secret; Secrets verb is `create` only.** `apply` plus an ownerReference patch would need `get`/`patch` on Secrets, letting the dispatcher read `fleet-azdo` and `fleet-vault-writer`. Changed during T6.
- **The PAT is mounted in the agent container.** The agent must push and open PRs, so it needs the PAT anyway. The PAT's scope is minimised and documented. Workload identity is a follow-up.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Prompt injection reads the user's token or the PAT inside the pod | Egress allowlist through the proxy; per-Job Secret deleted with the Job; vault credential absent from the agent container; README documents revoke and re-register |
| Two codex dispatches race past the serial check | Accepted for v1: the window is seconds wide and the cost is one rejected refresh. Documented |
| A Squid allowlist misses a Codex refresh host | README lists the initial hosts; the proxy logs denied CONNECTs; the build captures hosts from a test run |
| AssignedTo `uniqueName` differs from the UPN (guest or MSA accounts) | The credential check fails with a clear message (FR-4e), never falling back to another user; documented under A1 |
