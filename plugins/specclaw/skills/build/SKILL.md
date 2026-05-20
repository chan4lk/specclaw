---
description: Implement planned tasks by executing them wave-by-wave, committing each, and logging errors and learnings. Reads tasks.md and drives the build loop. The longest-running phase of the specclaw lifecycle. Run after /specclaw:plan has produced spec.md, design.md, and tasks.md.
---

# specclaw build

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Execute the planned tasks.

## Step 0 — Validate

Run `specclaw-validate-change .specclaw <change> build`. If it fails, report missing prerequisites and stop.

## Step 1 — Setup

```bash
specclaw-build setup .specclaw <change>
```

Returns JSON config with `parallel_tasks`, `models.coding`, `git.strategy`, `notifications.channel`. Capture this — you'll use `parallel_tasks` and `model` throughout the build.

**Worktree strategy:** when `git.strategy: worktree-per-change`, setup creates an isolated worktree at `.specclaw/worktrees/<change>/`. Use the `worktree_path` from the JSON as the working directory when spawning coding agents.

Send a **build started** notification:

```
🦞 **Build Started**
**Change:** <change>
**Branch:** specclaw/<change>
**Tasks:** <total_count> across <wave_count> waves
```

## Step 2 — Parse tasks

```bash
specclaw-parse-tasks --status pending .specclaw/changes/<change>/tasks.md
```

Outputs JSON: `[{"id":"T1","title":"...","wave":1,"depends":[],"files":[...],"estimate":"small"}, ...]`.

**Retry:** to re-run failed tasks, parse with `--status failed`, reset each to `pending` via `specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> pending`, then re-parse with `--status pending`.

## Step 3 — Wave loop

For each wave number (1, 2, 3, ...):

**a.** Filter tasks for this wave:
```bash
specclaw-parse-tasks --wave N --status pending .specclaw/changes/<change>/tasks.md
```
If empty, the build is complete — skip to Step 4.

**b.** Skip blocked tasks: if a task's dependency failed in a prior wave, mark it failed:
```bash
specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> failed
```

**c.** For each task in the wave (up to `parallel_tasks` concurrent):

1. Mark in-progress:
   ```bash
   specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> in_progress
   ```
2. Build the agent context payload:
   ```bash
   specclaw-build-context .specclaw <change> <TASK_ID>
   ```
3. Spawn a coding agent with that payload as the task. Use the model from config. Run independent tasks in parallel up to `parallel_tasks`.

**d.** Wait for all agents in the wave to complete.

**e.** For each succeeded agent:
   1. Mark complete: `specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> complete`. If the task previously failed, run `specclaw-log-error .specclaw <change> --resolve <TASK_ID>`.
   2. Commit: `specclaw-build commit .specclaw <change> <TASK_ID> "<title>" <files...>`.
   3. Notify: `✅ Task Complete: <TASK_ID> — <title>`.

**f.** For each failed agent:
   1. Mark failed: `specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> failed`.
   2. Log: `specclaw-log-error .specclaw <change> <TASK_ID> <wave> <agent_label> "<summary>"`.
   3. Update status.md with the failure reason.
   4. Notify: `❌ Task Failed: <TASK_ID> — <title>`.
   5. Mark dependent tasks in later waves as skipped/failed.
   6. **GitHub sync** (if enabled): `specclaw-gh-sync comment .specclaw <change> "❌ Task <TASK_ID> failed: <summary>"`.
   7. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue comment .specclaw <change> "❌ Task <TASK_ID> failed: <summary>"`.

**g.** GitHub sync (if enabled): `specclaw-gh-sync update .specclaw <change>` to refresh task checkboxes.
**g'.** Azure Boards sync (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the latest task checklist; optionally `specclaw-azdo-issue comment .specclaw <change> "Wave <N> complete: <X>/<total> tasks done"`.

**h.** Repeat for the next wave.

## Step 4 — Finalize

```bash
specclaw-build finalize .specclaw <change>
```

Runs the configured `test_command` (if any) and merges the branch per `git.strategy`.

## Step 5 — Post-build review

If `automation.post_build_review: true`:

**a.** Scope deviation: compare `git diff --name-only main...HEAD` against files declared in tasks. Flag any file modified but not declared.

**b.** Evaluate the build (~150 words):
- Were any spec requirements ambiguous or incomplete?
- Did the design need adjustment during build?
- Were any files modified outside declared scope?
- Did any agents struggle with context?
- Any reusable patterns discovered?

Log each finding:
```bash
specclaw-log-learning .specclaw <change> <category> <priority> "<detail>" "<action>"
```

**c.** Auto-log scope deviations as `design_gap`:
```bash
specclaw-log-learning .specclaw <change> design_gap medium "File <path> modified but not declared in any task" "Review task file declarations"
```

**d.** Pattern scan: `specclaw-detect-patterns .specclaw scan <change>`.

**e.** If any pattern has recurrence ≥ 3, alert the user.

## Step 6 — Update dashboard

```bash
specclaw-update-status .specclaw
```

## Step 7 — Notify

Send a final **build summary**:

```
🦞 **Build Complete**
**Change:** <change>
**Status:** <succeeded|partial|failed>
**Tasks:** <completed>/<total> complete, <failed> failed, <skipped> skipped
**Branch:** specclaw/<change> → merged
```

## Key Principles

- **Fresh context always** — each agent gets ONLY what `specclaw-build-context` produces. No stale context.
- **Parallel within waves, sequential across waves.**
- **Fail-fast on dependencies** — if a task fails, all dependents are immediately marked failed.
- **Agent guardrails** — every coding agent is auto-prepended four behavioral rules (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution), vendored verbatim from Andrej Karpathy's CLAUDE.md. See `references/agent-guardrails.md`. Injection happens inside `specclaw-build-context`; no config flag.
