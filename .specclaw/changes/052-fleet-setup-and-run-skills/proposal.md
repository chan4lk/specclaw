# Proposal: specclaw-fleet setup and run skills

**Created:** 2026-11-07
**Status:** ✅ Approved

## Problem

Standing up specclaw-fleet took a long, hand-driven session. Driving one change through it took nine pipeline runs.

The live end-to-end test (Rancher Desktop K3s, Azure DevOps `BistecGlobal/Product-Portal`, Key Vault, `demo-studio`) worked, but every step was improvised from the README. Each one hit a pitfall that a skill should already know about:
- the wrong kube context, which here was a real remote cluster;
- an Azure identity with no rights in the chosen subscription;
- an AzDO identity that differed from the Azure admin;
- the `kubectl apply` ordering;
- the Kubernetes service-connection scheme name;
- the agent ignoring `.path`;
- credential prompts that cannot run under `!`.

Triggering a change is just as manual. It means creating the work item, assigning it, having the assignee add `fleet:auto`, clearing stale `fleet:dispatched`/`fleet:refused` tags, queueing the pipeline, then watching the Job and the work item.

The test also found that the per-run review budget was read as a lifetime budget. The agent counted earlier runs' rounds and fixed nothing.

## Proposed Solution

Add two skills and two small CLI subcommands to `plugins/specclaw-fleet`, stacked on 049's branch.

1. **`specclaw-fleet doctor`** is a read-only check of the whole chain. It prints one line per item, `ok`/`missing`/`wrong` plus the fix, and touches nothing. Checks:
   - the kube context is the fleet cluster, not merely the current one;
   - fleet namespaces, RBAC, proxy and NetworkPolicy are present;
   - the runner image exists in the cluster's engine;
   - `fleet-azdo` and `fleet-vault-writer` secrets are present, by keys only;
   - the vault is reachable and a user is onboarded;
   - the AzDO agent is online;
   - both service connections are ready;
   - the pipeline exists.
2. **`specclaw-fleet:setup` skill** takes the operator through each `doctor` line that isn't `ok`, in order, until `doctor` is clean.
   - **Isolation:** a dedicated kubeconfig and a dedicated `AZURE_CONFIG_DIR`, so the operator's other contexts and accounts are never touched.
   - **What it does itself:** applies `k8s/`, builds and loads the image with the right `TARGETARCH`, creates the vault and the two service principals in a resource group the operator names, onboards users with `--writer`, creates the service connections (Kubernetes scheme `Kubernetes`, with a token for the dispatcher service account), and creates the pipeline.
   - **What it hands to the operator:** every credential step (`specclaw-fleet login`, PAT entry, agent `config.sh`) is given as an exact command for **a real terminal**, never `!`.
   - **Safety:** each step is idempotent, re-running skips finished work, and it stops and asks before any outward-facing action.
3. **`specclaw-fleet trigger <change>`** with a **`specclaw-fleet:run` skill**.
   - For an approved change, it ensures a work item exists and is assigned.
   - It checks that `fleet:auto` was added by the assignee. If not, it says who must add it and stops, because consent can't be added on someone's behalf.
   - It checks that the assignee's credential is registered.
   - It clears `fleet:dispatched`/`fleet:refused` only when `--retry` is given.
   - It then queues the pipeline, or dispatches directly with `--direct`.
   - The skill watches the Job and the work item and reports the outcome: a PR (real or draft) with its link, or the recorded failure and the agent-log tail.
4. **Prompt fix:** the review fix-round budget is **per run**.

## Scope

### In Scope
- `bin/specclaw-fleet doctor` and `bin/specclaw-fleet trigger`, plus their lib files, each 80 lines or fewer.
- `skills/setup/SKILL.md` and `skills/run/SKILL.md`.
- Tests that stub `kubectl`, `az`, `curl` and `docker`: each doctor item, a doctor run that mutates nothing, every trigger gate, and the per-run prompt wording.
- README: replace the hand-written setup section with "run `/specclaw-fleet:setup`", and document `trigger` and `doctor`.
- Entrypoint prompt: budget wording only.

### Out of Scope
- Changes to dispatch, the image's security model, or the core `plugins/specclaw/`.
- Cloud-managed clusters (AKS and similar) and Helm charts. K3s and Rancher Desktop are the documented path; others go through the same `doctor` lines by hand.
- Creating Azure subscriptions or resource groups, or granting the operator rights. `setup` stops and says what's missing.
- Pushing the 049 branch or opening its PR.

## Impact

- **Size:** bounded. It adds two subcommands and two skills to an existing plugin, without changing any interface others depend on.
- **Files affected:** ~10 (estimated)
- **Complexity:** medium
- **Risk:** medium. `setup` drives outward-facing actions (Azure resources, AzDO service connections). The guard is a confirmation before each one, plus `doctor` as the read-only source of truth.

## Open Questions

- **Decided (2026-11-07):** `trigger` refuses an unapproved proposal; approval stays a human lifecycle step.
- **Decided (2026-11-07):** `setup` installs the AzDO agent as a service (`svc.sh install`) by default. It honours `.path` and survives logout.
- **Decided (2026-11-07):** `doctor` stays in `specclaw-fleet`.
- Raised at approval: whether a Microsoft-hosted agent can dispatch to a remote K3s cluster (Hetzner) instead of a self-hosted agent. Answered in the session; not in this change's scope unless added.
