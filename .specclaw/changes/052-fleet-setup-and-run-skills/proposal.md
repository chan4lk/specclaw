# Proposal: specclaw-fleet setup and run skills

**Created:** 2026-11-07
**Status:** ✅ Approved (revised 2026-11-07: Microsoft-hosted agent, remote Hetzner cluster, public GHCR image)

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
5. **Default mode: Microsoft-hosted agent and a remote cluster.** The local self-hosted agent stays as the alternative mode.
   - **Cluster:** first target is `bistec-dev-uat` (Hetzner, k3s, 2 amd64 nodes, public API on 6443). No Tailscale for now; it is documented as the next hardening step.
   - **Cluster access:** the Kubernetes service connection uses a kubeconfig with the least-privilege `fleet-dispatcher` token (create Jobs and Secrets in `specclaw-fleet` only), short-lived and rotated by `setup`.
   - **Pipeline:** runs on `ubuntu-latest`. A step fetches specclaw (`specclaw-fleet` + `specclaw-sync`) at a pinned ref instead of relying on agent PATH. `kubectl`, `az` and `jq` come from the hosted image.
   - **Image:** a **public** GHCR image, `ghcr.io/chan4lk/specclaw-fleet:<tag>`, built for `linux/amd64` and `linux/arm64` by a GitHub Actions workflow in the public specclaw repo. It contains **no Claude Code binary**: the Anthropic docs are silent on redistributing it.
     - At pod start, the entrypoint downloads the pinned version (`FLEET_CLAUDE_VERSION`) from `downloads.claude.ai`, which is already on the allowlist, into the pod's writable home.
     - It checks the GPG signature of the release `manifest.json` against Anthropic's key fingerprint `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`, then the binary's SHA256 from that manifest. Any mismatch fails the run (`exit=claude-verify-failed`).
     - The download time is recorded on the work item (`claude_fetch_s`), so latency is visible per run.
     - `DISABLE_UPDATES=1` blocks every self-update path in the pod.
     - Public images need no pull secret. `FLEET_IMAGE_PULL_SECRET` stays optional, for private registries.
   - **Node isolation:** the cluster also runs `argocd`, `nexus-dev` and `nexus-uat`, and fleet pods run agent code that prompt injection could steer. `setup` offers to pin fleet Jobs to a labelled, tainted node, and the Job gets the matching `nodeSelector` and toleration when the label exists.
   - **doctor** gains checks for the registry and pull secret, the node pinning, the pipeline's pinned ref, and the cluster's NetworkPolicy enforcement (a short-lived probe pod: proxy reachable, direct egress blocked).

## Scope

### In Scope
- `bin/specclaw-fleet doctor` and `bin/specclaw-fleet trigger`, plus their lib files, each 80 lines or fewer.
- `skills/setup/SKILL.md` and `skills/run/SKILL.md`.
- Tests that stub `kubectl`, `az`, `curl` and `docker`: each doctor item, a doctor run that mutates nothing, every trigger gate, and the per-run prompt wording.
- README: replace the hand-written setup section with "run `/specclaw-fleet:setup`", and document `trigger` and `doctor`.
- Entrypoint prompt: budget wording only.
- Pipeline template: a hosted-agent variant (`ubuntu-latest`, pinned specclaw fetch); the self-hosted variant stays.
- Dispatch: an optional `FLEET_IMAGE_PULL_SECRET`, plus `nodeSelector` and toleration from `FLEET_NODE_LABEL`, in the rendered Job, with tests. Both are empty by default; node pinning comes later, once a dedicated worker exists.
- Runner image: the claude binary is removed from the Dockerfile. The entrypoint gains fetch-and-verify of the pinned claude with timing, plus `DISABLE_UPDATES=1`. A `.github/workflows/fleet-image.yml` builds multi-arch and pushes to GHCR on a tag or by manual dispatch. Tests cover verify pass, a bad signature, a bad checksum, and the timing field.

### Out of Scope
- Changes to dispatch, the image's security model, or the core `plugins/specclaw/`.
- Tailscale or any private API path. It is documented as the next step, not built here.
- Cloud-managed clusters (AKS and similar) and Helm charts. K3s and Rancher Desktop are the documented path; others go through the same `doctor` lines by hand.
- Creating Azure subscriptions or resource groups, or granting the operator rights. `setup` stops and says what's missing.
- Pushing the 049 branch or opening its PR.

## Impact

- **Size:** architectural. Besides the subcommands and skills, it adds a second deployment mode (hosted agent, remote cluster, registry) and new dispatch inputs (pull secret, node pinning).
- **Files affected:** ~16 (estimated)
- **Complexity:** medium
- **Risk:** medium to high. A public API server and a cluster shared with UAT workloads; mitigated by the least-privilege, short-lived dispatcher token, NetworkPolicy, optional node pinning, and Tailscale as the follow-up. `setup` drives outward-facing actions (Azure resources, AzDO service connections). The guard is a confirmation before each one, plus `doctor` as the read-only source of truth.

## Open Questions

- **Decided (2026-11-07):** `trigger` refuses an unapproved proposal; approval stays a human lifecycle step.
- **Decided (2026-11-07):** `setup` installs the AzDO agent as a service (`svc.sh install`) by default. It honours `.path` and survives logout.
- **Decided (2026-11-07):** `doctor` stays in `specclaw-fleet`.
- **Decided (2026-11-07):** the default is a Microsoft-hosted agent and the remote `bistec-dev-uat`, over its public API, without Tailscale for now.
- **Decided (2026-11-07):** registry is public GHCR, with the claude binary fetched and verified at pod start (latency measured). This was chosen over a private ACR with the binary baked in.
- **Decided (2026-11-07):** node pinning is supported but left empty; a dedicated worker will be added later.
