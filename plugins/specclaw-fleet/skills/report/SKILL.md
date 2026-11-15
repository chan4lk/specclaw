---
description: Use when someone asks how a specclaw-fleet build went, wants to see the fleet build timeline, cost, agent time or review rounds, or asks for the fleet pane or a build report page.
---

# specclaw-fleet report

Shows a fleet build: when each change's pipeline, agent run and PR happened, plus totals. It only reads, from the work-item run records first, then AzDO PRs and pipeline runs, then the cluster for runs still going.

## 1. Pick the scope

- Nothing named: the **latest build**, meaning approved changes dispatched within 12h of the newest dispatch.
- Named changes: `specclaw-fleet report <change>...`.
- A feature: `specclaw-fleet report --feature <module>`. Its rows carry their wave.
- Add `--since <UTC ISO>` to drop runs dispatched earlier.

## 2. Run it

```bash
specclaw-fleet report [<scope>] --save
```

`--save` writes `.specclaw/fleet/report.json` (gitignored in its own folder). That snapshot is what the `/fleet-pane` pane, the band above the prompt and the `fleet: N running` status line read. Those views never run commands themselves.

When the user wants a page to share or open in a browser, add `--html <file>`. It writes one self-contained page with no network, holding the timeline by wave, the lifecycle table and the totals. Offer to publish it only if they ask.

## 3. Report back

- In Claude Code, tell the user to run `/fleet-pane` to see the timeline beside the chat. On Codex, point them at the `--html` file instead.
- Summarise in at most 5 lines: wall clock, Jobs, agent time, hosted minutes, review rounds and commits, PRs open or merged, and cost.
- Always call cost an **API-equivalent estimate**. Setup-token runs are not billed per token.
- Name any change that ended `failed` with its `exit`.

Runs from before specclaw-fleet 0.9.1 lack agent times, cost and review rounds. Their rows fall back to record times, and those columns stay `-`.
