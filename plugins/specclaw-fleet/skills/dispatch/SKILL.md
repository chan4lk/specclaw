---
description: Use when an approved specclaw change should run headless in a sandboxed K3s job with Claude or Codex, on the work-item assignee's own plan.
---

# specclaw-fleet dispatch

Hands one approved change to the cluster and returns immediately. The run itself happens in a K8s Job; its progress is recorded on the change's Azure Boards work item, never polled.

```bash
specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>] [--vault <name>] [--dry-run] [--force]
```

Dispatch refuses, and creates nothing, when:

- the proposal is not approved, or the change has no work item;
- the work item has no assignee;
- no `fleet:auto` tag at all: skipped quietly (exit 3), nothing written;
- a `fleet:auto` tag added by someone other than the assignee, or a history that cannot be read: refused (exit 4);
- the assignee has no registered credential for the agent (`specclaw-fleet login`);
- `--agent codex` while that assignee already has an unfinished codex job (exit 5, retry later).

Refusals (exit 4) set the work item to `Failed` with the reason and tag it `fleet:refused`; a quiet skip (exit 3) writes nothing. Dispatch never falls back to anyone else's credential.

On success it prints one JSON line: `{"ok":true,"job":…,"agent":…,"work_item":…}`. Use `--dry-run` to see the rendered Secret (redacted) and Job without applying them.

Each run spends the assignee's own 5-hour and weekly plan allowance. Say so when you dispatch for someone.

Exit codes:
- `0`: dispatched; the work item was claimed atomically with `fleet:dispatched`.
- `3`: already handled (`fleet:dispatched` or `fleet:refused`). Pass `--force` to dispatch again.
- `4`: refused; the work item is set to `Failed` and tagged `fleet:refused`.
- `5`: the assignee's codex slot is busy. Nothing is tagged, so retry later.
- `1`: error.

Settings come from flags or environment variables: `FLEET_VAULT`, `FLEET_DEFAULT_AGENT`, `FLEET_REF`, `FLEET_IMAGE`, `FLEET_NAMESPACE`, `FLEET_DEADLINE_MINUTES`, `FLEET_KUBE_CONTEXT`, `FLEET_CLAUDE_VERSION` (required for claude jobs), and the optional `FLEET_IMAGE_PULL_SECRET` and `FLEET_NODE_LABEL` (`key=value`). Each one can also be set in the `fleet:` block of `.specclaw/config.yaml` (precedence: flag, then env, then config), along with `cluster_name` (`FLEET_CLUSTER_NAME`), `pipeline_file` (`FLEET_PIPELINE_FILE`) and `kubeconfig` (`KUBECONFIG`). `kube_context` and `kubeconfig` from config are ignored inside a pipeline run (`TF_BUILD` set). Setup is in the plugin's `README.md`.
