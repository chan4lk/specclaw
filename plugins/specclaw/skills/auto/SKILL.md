---
description: Run the propose → plan → build → verify lifecycle autonomously across the queue of active changes. Advanced — requires automation config in config.yaml. Use when you want specclaw to advance every change to its next phase without prompting; do not use for a single targeted change (use the specific verb instead).
disable-model-invocation: true
---

# specclaw auto

Run the lifecycle autonomously for the active queue.

1. Read `.specclaw/STATUS.md` for the next actionable item across changes.
2. For each change, advance it to its next phase:
   - Proposal exists without plan → run `/specclaw:plan`.
   - Plan exists without implementation → run `/specclaw:build`.
   - Built without verification → run `/specclaw:verify`.
3. Respect `config.yaml` limits:
   - `automation.max_tasks_per_run` — cap on total tasks executed this run.
   - `automation.auto_verify` — whether to chain verify after build.
   - `automation.auto_archive` — whether to chain archive after a passing verify.
4. Notify the user of results via the configured notification channel.

Stop and surface the issue if any phase fails, rather than blindly advancing to the next change.
