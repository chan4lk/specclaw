---
description: Use when an approved specclaw change should run headless in a sandboxed K3s job with Claude or Codex, on the work-item assignee's own plan.
---

# specclaw-fleet dispatch

Hands one approved change to the cluster and returns immediately. The run itself happens in a K8s Job; its progress is recorded on the change's Azure Boards work item, never polled.

```bash
specclaw-fleet dispatch <change> [--agent claude|codex] [--ref <branch>] [--vault <name>] [--dry-run]
```

Dispatch refuses, and creates nothing, when:

- the proposal is not approved, or the change has no work item;
- the work item has no assignee;
- the assignee has not consented: no `fleet:auto` tag, and they did not trigger the run themselves;
- the assignee has no registered credential for the agent (`specclaw-fleet login`);
- `--agent codex` while that assignee already has an unfinished codex job.

The last four also set the work item to `Failed` with the reason. Dispatch never falls back to anyone else's credential.

On success it prints one JSON line: `{"ok":true,"job":…,"agent":…,"work_item":…}`. Use `--dry-run` to see the rendered Secret (redacted) and Job without applying them.

Each run spends the assignee's own 5-hour and weekly plan allowance. Say so when you dispatch for someone.

Defaults come from `.specclaw/config.yaml`: `fleet.default_agent`, `fleet.namespace`, `fleet.image`, `fleet.vault`, `fleet.deadline_minutes`. Setup is in the plugin's `README.md`.
