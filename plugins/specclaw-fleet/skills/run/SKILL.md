---
description: Use when someone wants an approved specclaw change run headless by specclaw-fleet, wants to retry a fleet run, or asks how a fleet run went.
---

# specclaw-fleet run

Puts one approved change through the fleet and reports what happened. Each run spends the **assignee's** Claude plan, so say so before you trigger.

## 1. Trigger

```bash
FLEET_VAULT=<vault> specclaw-fleet trigger <change> [--create] [--retry] [--direct]
```

| Exit | Meaning | What to do |
|---|---|---|
| 0 | queued (`{"mode":"pipeline","run":…}`) or dispatched (`--direct`) | watch it (step 2) |
| 1, `proposal is not approved` | lifecycle gate | approve through `/specclaw:propose`; never approve on someone's behalf |
| 1, `pass --create` | no work item | re-run with `--create` |
| 1, `has no assignee` | nobody's plan to run it on | ask who owns it; assign in Boards |
| 4, `must add the fleet:auto tag` | consent missing | the **assignee** adds `fleet:auto` in Boards. Nobody else can add it for them. |
| 1, `specclaw-fleet login` | no registered credential | the assignee runs `specclaw-fleet login --agent claude` in a real terminal |

A change already tagged `fleet:dispatched` or `fleet:refused` is skipped by dispatch. Pass `--retry` to clear both tags.

## 2. Watch

- **Pipeline:** `az pipelines runs show --id <run>` until it completes. Its log names the Job (`{"job":"fleet-…"}`).
- **Job:** use the fleet kubeconfig. `kubectl -n specclaw-fleet get job <job>` shows the outcome. `kubectl logs <pod> -c agent` ends with the agent's own summary, with tokens redacted.
- **Work item:** its comments record each step:
  - `dispatched`
  - `running` (with `claude_fetch_s`, the per-run Claude download time)
  - `pr_open`, or `failed` with an `exit=` reason.

## 3. Report

Lead with the outcome:
- **PR:** link it, and say whether it is a **draft**. Every finished run that pushed work gets a PR: a real one when verify passed, a draft one otherwise.
- **Failure:** quote the `exit=` reason. `egress-not-ready`, `claude-verify-failed`, `clone-failed` and `not-approved-at-ref` are infrastructure or gate stops. Anything else is in the agent summary.

Then give the open findings from the PR description or `follow-ups.md`, and the next step: merge, retry with `--retry`, or fix on the branch. Work always lands on the change branch, and a retry resumes it.
