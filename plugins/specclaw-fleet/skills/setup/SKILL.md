---
description: Use when someone wants to set up, repair or check specclaw-fleet infrastructure (cluster, image, Key Vault, AzDO pipeline and service connections) so approved changes can run headless.
---

# specclaw-fleet setup

The goal is a clean `specclaw-fleet doctor`. Run it first, then fix every line that isn't `ok`, in the order printed, and run it again after each fix. Re-running the skill skips work that's already done.

**Record every confirmed value in `.specclaw/config.yaml` as you go**, under `fleet:`. That covers `vault`, `cluster_name`, `image`, `claude_version`, `pipeline` and `pipeline_file`. The connection names go in the pipeline YAML only. After that, `specclaw-fleet doctor`, `trigger`, `optin` and `status` need no env prefix. Which cluster this machine uses is local: write `FLEET_KUBE_CONTEXT` and `KUBECONFIG` (the isolated kubeconfig) to the gitignored `.specclaw/.env`, never to `fleet:`. Never write a secret in `fleet:`: the PAT goes in the gitignored `.specclaw/.env`, and credentials go in Key Vault. Commit the config change, asking before you push.

## Rules

- **Isolate.** Write a dedicated kubeconfig (`kubectl config view --minify --flatten --context <ctx>`) and use a dedicated `AZURE_CONFIG_DIR`. Never switch the operator's current kube context or az account. Their default context may be a production cluster.
- **Ask before anything outward-facing**: Azure resources, role assignments, GHCR pushes or visibility changes, AzDO service connections, pipelines, and pushes to a repo. One question per action, naming exactly what gets created.
- **Credentials are the operator's.** Give `specclaw-fleet login`, PAT entry and agent `config.sh` as exact commands for **a separate, real terminal**. Never run them with `!`: those commands get no TTY, and they hang.
- **Never print a secret.** Read service-principal credentials from `0600` files straight into `kubectl create secret … --from-file`.

## Defaults to confirm up front

- **Mode:** hosted, the default (Microsoft-hosted AzDO agent, remote cluster, public GHCR image), or local (self-hosted agent on this machine, Rancher Desktop).
- **Cluster:** the cluster context, the Azure subscription and resource group (the operator must be able to create resources and role assignments there), the AzDO org and project, and the Claude version to pin (`FLEET_CLAUDE_VERSION`).
- **Identities:** the AzDO identity that work items are assigned to must be the same UPN that is onboarded in the vault. The Azure admin identity may be a different one.

## Fixes, by doctor line

| doctor line | Fix |
|---|---|
| `context` | Make the isolated kubeconfig for the chosen context and set `FLEET_KUBE_CONTEXT`. |
| `namespaces`, `rbac`, `egress`, `netpol` | `kubectl apply -f plugins/specclaw-fleet/k8s/` (`00-namespace.yaml` sorts first). Then wait for the proxy. Probe with a labelled pod: wait about 8 s for kube-router, check the proxy answers and direct egress is refused. |
| `image` | In the specclaw repo, push a `fleet-v<tag>` tag or run the `fleet-image` workflow. On first push, set the GHCR package to **public** (Package settings → Change visibility); ask first. The image contains no Claude binary. Each pod fetches `FLEET_CLAUDE_VERSION` and verifies it against Anthropic's signed manifest. |
| `vault` | `az keyvault create --enable-rbac-authorization true`, then grant yourself `Key Vault Administrator` on it. Create the **writer** service principal with no role and the **dispatch** service principal with `Key Vault Secrets User` on the vault plus `Reader` on the resource group. Then run `specclaw-fleet onboard <upn> --vault <v> --writer <writer-object-id>` for each person. Each person then runs `specclaw-fleet login --agent claude` in a real terminal. |
| `secret:fleet-vault-writer` | Create it from the writer service principal's file: tenant, client id and secret. |
| `secret:fleet-azdo` | Have the operator paste a PAT (Code read/write, Work Items read/write) at a hidden prompt in a real terminal. The prompt writes the secret, plus `.specclaw/.env` in the repo, which must be gitignored first. |
| `service-connections` | **Kubernetes:** scheme `Kubernetes`, `authorizationType: Kubeconfig`. Use a kubeconfig with a `kubectl create token fleet-dispatcher --duration=…` token, never an admin kubeconfig, and rotate it before it expires. **ARM:** the dispatch service principal. Enable both for pipelines. |
| `pipeline` | Copy `pipelines/dispatch-hosted.yml` (or `dispatch.yml` for local mode) into the repo and set its variables. `fleetSpecclawRef` must be a **full 40-character commit SHA** of specclaw: the pipeline refuses tag names and verifies the fetched commit. Push after asking, then `az pipelines create --skip-first-run`. A root-level `pool:` cannot use a template expression. |

## Repo config

Set these in `.specclaw/config.yaml`:
- `azdo.enabled`, plus `org`, `project` and `repo`;
- `azdo.boards.sync: true`, with a `work_item_type` that exists in the process (Basic: `Issue`);
- `azdo.fleet_states` mapped to real states;
- `pr.test_policy` set, so PRs never prompt;
- `git.base_branch`.

## Local mode only

Register the agent with `config.sh`, which the operator runs. Then install it with `svc.sh install`: an interactive `run.sh` ignores `.path`, and fleet needs `specclaw-fleet` and `specclaw-sync` on the agent's PATH.

Finish when `doctor` prints `doctor: all checks ok`. Then use `/specclaw-fleet:run`.
