---
description: Use when someone wants one or more approved specclaw changes run headless by specclaw-fleet, wants to opt changes in or retry a fleet run, or asks what is happening on the fleet cluster.
---

# specclaw-fleet run

Puts one or more approved changes through the fleet and watches them through to the end. Settings come from the `fleet:` block in `.specclaw/config.yaml`, so commands need no env prefix. If `doctor` fails, use `/specclaw-fleet:setup` first.

## 1. Look

Run `specclaw-fleet status <change>...`, or `status` with no arguments to see every approved change.
- `not-opted-in`: the work item lacks `fleet:auto`.
- `no work item`: the change has no work item yet. Run `specclaw-fleet trigger <c> --create`, then opt it in.

## 2. Opt in (one confirmation)

1. Run `specclaw-fleet optin <change>... --dry-run`. It names **the caller** (the `AZDO_TOKEN` identity) and what it will do for each item.
2. Show that plan and ask **once**. Say that every run spends the **caller's** Claude or Codex plan, and that the caller's UPN must be the one onboarded in the vault.
3. On a yes, run `specclaw-fleet optin <change>...`.

Rules:
- Never assign an item to someone else.
- Never opt in an item assigned to someone else. `optin` refuses it (exit 4). Tell the user who has to opt in.

## 3. Trigger

Trigger in **parallel** by default: `specclaw-fleet trigger <c>` for each change, then go to step 4.

Before triggering, warn about two things:
- every parallel run spends the caller's plan at the same time;
- changes that touch the same area each branch from the base and may produce PRs that conflict.

With `--sequential`, or when the user asks for it, trigger one change, watch it to the end, then trigger the next.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | queued (or dispatched with `--direct`) | watch it |
| 1, `no change … on <remote>/<ref>` | the change name is wrong, or it isn't pushed | check the name; push |
| 1, `not approved on <remote>/<ref>` | approval is read from the pushed ref | approve through the lifecycle and push; never approve for someone |
| 3, `not opted in` | no `fleet:auto` | step 2 |
| 3, `already handled` | tagged `fleet:dispatched` or `fleet:refused` | `--retry` |
| 4 | no assignee, someone else's consent, or no registered credential | the assignee assigns the item, opts in, or runs `specclaw-fleet login` in a real terminal |
| 5 | codex slot busy | retry after the earlier run |

## 4. Watch

Note the time you triggered, then run `specclaw-fleet status <change>... --watch 30 --since <that time>`. It returns once every change has ended: `pr_open`, `failed` (including refusals), a failed Job, `did-not-run` (its pipeline run completed without dispatching it, e.g. a busy codex slot or a pipeline error; open that run's log), `not-opted-in`, or `no work item`. It always returns: after `--timeout` minutes (default: the run deadline plus 20) it exits 2 and names the changes still running.
- **Row columns:** each row shows the work item, its fleet tags, the last record (`dispatched`, `running`, `pr_open` or `failed`, with `exit=`), and the newest Job with its pod phase.
- **Pipeline:** the header line shows the latest pipeline run.
- **Detail:** use `kubectl -n specclaw-fleet logs <pod> -c agent` with the fleet kubeconfig. It ends with the agent's summary, with tokens redacted.

## 5. Report

For each change, lead with the outcome:
- **PR:** link it, and say whether it is a **draft**. A draft means verify didn't pass, and the work is still on the branch.
- **Failure:** quote the `exit=` reason.
  - `egress-not-ready`, `clone-failed`, `resume-failed`, `not-approved-at-ref` and `claude-fetch-failed` are infrastructure or gate stops.
  - `claude-verify-failed` is a security event.
  - Anything else is explained in the agent summary.

Then give the open findings (from the PR description or `follow-ups.md`) and the next step: merge, `trigger --retry` (which resumes the branch), or fix on the branch.
