# Proposal: specclaw-fleet — self-hosted Azure Pipelines agents and minute-lean pipelines

**Created:** 2026-11-07
**Status:** ✅ Approved

## Problem

Microsoft-hosted agents in a private project come with 1,800 free minutes a month. After that you pay per parallel job. Self-hosted agents have no time limit. The org gets one free self-hosted parallel job, plus one for each Visual Studio Enterprise subscriber, and extra self-hosted parallel jobs cost less than Microsoft-hosted ones.

The pipelines from 049 and 050 also spend agent time on work that needs no agent: REST calls, approvals and waits.

## Proposed Solution

Add to `specclaw-fleet`:

1. **Azure Pipelines agent kit for the same K3s cluster.**
   - An agent image based on Microsoft's Docker agent guide, started with `--once` so every job gets a fresh pod.
   - A KEDA `ScaledJob` using the `azure-pipelines` scaler, which scales from zero to `maxReplicaCount`. That value should equal the purchased self-hosted parallel jobs.
   - Service-principal registration (`AZP_CLIENTID`, `AZP_CLIENTSECRET`, `AZP_TENANTID`, Agent Pools read and manage) instead of a PAT.
   - A namespace separate from the fleet jobs. Agents hold pipeline secrets and fleet pods hold users' plan tokens, so the two never share an image or namespace.
2. **Minute-lean pipeline templates.** The 049 and 050 templates are rewritten so that:
   - REST calls, work-item updates and approvals run in `pool: server` agentless jobs (`InvokeRESTAPI`, `ManualValidation`);
   - only `dispatch` needs an agent, and it runs for seconds;
   - no job polls: progress arrives through service hooks and the fleet job's own work-item updates;
   - checkout uses `fetchDepth: 1`;
   - path filters keep changes under `.specclaw/` from running full CI;
   - CI uses `batch: true` on busy branches.
3. **Cache in the cluster.** `--once` pods start cold, so ship manifests for a pull-through registry cache and an npm/NuGet mirror.

## Scope

### In Scope
- Agent Dockerfile, `start.sh`, KEDA `ScaledJob` and `TriggerAuthentication`, NetworkPolicy, and the cache/mirror manifests under `plugins/specclaw-fleet/k8s/azdo-agent/`.
- Reworked pipeline templates from 049 and 050, with an agentless-first layout.
- A setup guide section on counting the free parallel jobs (VS Enterprise seats) and sizing `maxReplicaCount`.

### Out of Scope
- Any change to the core `plugins/specclaw/`.
- Windows or macOS agents.
- Managed DevOps Pools or Azure VM scale-set agents. They are an alternative, documented in one line only.
- Buying parallel jobs. That is an org billing action.

## Impact

- **Size:** bounded. It is manifests and templates on top of 049 and 050, and adds no new interface.
- **Files affected:** ~8 (estimated)
- **Complexity:** small
- **Risk:** low. The main risk is that self-hosted agents build PR code inside the cluster; `--once` and the NetworkPolicy contain it.

## Open Questions

- Does KEDA ship with the target K3s clusters, or do we install it (Helm) as part of the kit?
- How many VS Enterprise subscribers does the org have? That sets the free parallel job count.
- Should the cache and mirror be optional, so a small team can skip them?

## Dependency Bypass

- Depends on **049** and **050** for the pipeline templates it reworks. The agent kit itself (item 1) has no dependency and could ship first.
