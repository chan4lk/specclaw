---
description: Autonomously iterate build→verify→review until every gate is green or a guardrail halts. Drives the specclaw-loop controller — evaluate gates, reflect, fix the smallest diff, re-verify the whole change, and repeat. Use when asked to loop, iterate until done, or keep fixing until tests pass / verify passes / review is clean. Default-on around /specclaw:build and /specclaw:verify.
---

# specclaw loop

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Autonomously drive the change to all-green. The **controller** (`specclaw-loop`) owns every mechanical decision — gate evaluation, signatures, caps, no-progress / regression / oscillation detection, the reward-hack guard, and state/log persistence. This skill only orchestrates the LLM steps: reflect, spawn a fix agent, commit. Follow the controller's JSON verbatim — do not second-guess a `halt`.

## Step 0 — Validate prerequisites

The loop presumes `/specclaw:plan` and at least one `/specclaw:build` pass have already run — it remediates an existing implementation, it does not create one. Confirm the change is built:

```bash
specclaw-validate-change .specclaw <change> verify
```

If it fails (tasks not all complete / no build), tell the user to run `/specclaw:build` first and stop.

Read `loop.enabled` from `.specclaw/config.yaml`:

```bash
grep -A1 '^loop:' .specclaw/config.yaml
```

If `loop.enabled` is `false`, tell the user the autonomous loop is disabled and to run `/specclaw:build` and `/specclaw:verify` normally, then **stop**. Otherwise continue.

## Step 1 — Init

```bash
specclaw-loop init .specclaw <change>
```

Seeds `loop-state.json` and `loop-log.md` (idempotent — never clobbers an existing state or log). Send a **loop started** notification:

```
🦞 **Loop Started**
**Change:** <change>
**Mode:** autonomous build→verify→review
**Caps:** max <loop.max_iterations> local iterations
```

## Step 2 — Local loop

Repeat up to `loop.max_iterations` (default 5). The controller enforces the cap in Step 2c — do not track it yourself.

**a. Evaluate gates:**

```bash
specclaw-loop gates .specclaw <change>
```

Parse the JSON: `{all_green, passing_count, gates:[{name,green,errors,files}]}`. The four gates are `tasks-complete`, `tests`, `verify`, `review`.

> To refresh the `verify` / `review` gate inputs, run `/specclaw:verify` first — it writes `verify-report.md` and (if `workflow.code_review: true`) `review-report.md`, which `gates` reads. On the first turn, run `/specclaw:verify` before this step so those gates have fresh reports.

**b. If `all_green` is `true`:**

```bash
specclaw-loop done .specclaw <change>
```

Send the printed PASS block as a **success notification**. Proceed to Step 3 (CI outer loop) if `loop.ci_gate: true`, else skip to Step 4.

**c. Else — compute the signature, then decide:**

```bash
sig=$(specclaw-loop signature .specclaw <change>)
specclaw-loop decide .specclaw <change> <passing_count> "$sig"
```

Parse `{action, reason}`. `passing_count` is the value from the gates JSON in Step 2a.

**d. If `action` is `halt`:**

```bash
specclaw-loop escalate .specclaw <change> "<reason>"
```

Paste the controller's stdout (the `🛑 LOOP HALTED` block) as the **escalation notification**. **STOP the loop.** Partial work is committed and the worktree/branch is preserved by the controller.

**e. Else (`action` is `continue`) — reflect, fix:**

1. From the red gates in the Step 2a JSON, write two files under the change dir:
   - a compact **reflection** (`.specclaw/changes/<change>/.loop-reflection.md`) — 2-4 sentences: what failed, the likely cause, and the smallest fix hypothesis.
   - a structured **failure record** (`.specclaw/changes/<change>/.loop-failure.txt`) — enumerate every red gate with its `name`, `errors`, and `files`. Concurrent failures (e.g. tests + review both red) go in one record.
2. Build the remediation payload (use the failing task id, or the change name if the failure spans the whole change):
   ```bash
   specclaw-build-context .specclaw <change> <task_or_change> \
     --failure-record .specclaw/changes/<change>/.loop-failure.txt \
     --reflection .specclaw/changes/<change>/.loop-reflection.md
   ```
3. Spawn a fix agent with that payload as the task. Use the model from config `models.coding`. Instruct it to make the **SMALLEST diff** that turns the red gate(s) green, touch no unrelated code, and **never modify test files to force a pass**. Additionally instruct it on reversibility: prefer local, reversible actions (editing files, running tests); do **not** take hard-to-reverse or externally visible actions to get a gate green — no deleting files or branches, no `git push --force`, no `git reset --hard`, no bypassing safety checks (e.g. `--no-verify`), no discarding unfamiliar files that may be in-progress work. If a gate seems to require such an action, halt and report instead — that is an escalation, not a fix.

**f. Reward-hack guard — run AFTER the fix agent, BEFORE committing:**

```bash
specclaw-loop guard-tests .specclaw <change>
```

If it exits **nonzero** (exit 3, `{tripped: true}`): the fix agent touched a test file. The controller has already reverted the illegal edit per `loop.guard_action`. Treat this turn as a **rejected, non-progress failure** — do NOT commit, log the turn (Step 2g with the same signature so `decide` catches the repeat), and continue the loop.

**g. Commit the fix turn and log it:**

```bash
git add -A && git commit -m "specclaw(<change>): loop fix — turn <N>"
specclaw-loop log-turn .specclaw <change> <passing_count> "$sig" <action> "<reflection>" "<gates_summary>"
```

`<gates_summary>` is a one-line-per-gate GREEN/RED summary from the Step 2a JSON. This appends a `## Turn N` section to `loop-log.md` and bumps `loop-state.json`.

**h. Loop** back to Step 2a — re-evaluate the **whole change** through all gates.

## Step 3 — CI outer loop (opt-in)

Only if `loop.ci_gate: true`, and only **after the PR branch is pushed** — cross-reference `/specclaw:pr`, which creates and pushes the PR. Repeat up to `loop.ci_max_iterations` (default 3):

**a. Poll one CI cycle** (blocks up to `loop.ci_timeout_seconds`, default 1200):

```bash
specclaw-loop ci-poll .specclaw <change>
```

Parse `{status, provider, failed_log, pr}`.

**b. Route on `status`:**
- `green` → CI passed; proceed to Step 4.
- `no-checks` → no pipeline attached; **warn** the user and proceed to Step 4 (treated as green after grace).
- `disabled` / `none` → CI not configured; proceed to Step 4.
- `red` → feed `failed_log` back as the failure record, run a fix cycle exactly as in Steps 2e–2g, `git push`, and re-poll (next iteration).
- `timeout` → hung pipeline; escalate (`specclaw-loop escalate .specclaw <change> "CI timeout after <ci_timeout_seconds>s"`) and STOP.

**c. If the `ci_max_iterations` cap is reached** without green → `specclaw-loop escalate .specclaw <change> "CI cap <ci_max_iterations> reached"`, paste the halt block, and STOP.

## Step 4 — Update dashboard

```bash
specclaw-update-status .specclaw
```

## Step 5 — Notify

Send a final **loop summary** (build-summary style):

```
🦞 **Loop Complete**
**Change:** <change>
**Status:** <PASS|HALTED>
**Turns:** <turns_used> / <loop.max_iterations>
**Gates:** tasks-complete · tests · verify · review — <all green | which red>
**Branch:** specclaw/<change>
```

On HALTED, also surface the escalation reason and point the user at `.specclaw/changes/<change>/loop-log.md`.

## Key Principles

- **Guardrails are enforced by the controller, not the prompt.** Caps, no-progress (identical/empty signature `loop.no_progress_limit` turns), regression (passing-gate count drops), and oscillation (A→B→A / Nth repeat) are code — a law, not a suggestion. When `decide` says `halt`, halt.
- **Reward-hack guard protects the tests.** `guard-tests` diffs the working tree against the configured `loop.test_paths` (plus built-in test globs) after every fix agent. Any test-file edit rejects the turn and reverts it (`loop.guard_action`, default `revert-tests`). Tests run from committed HEAD, never from agent-staged changes — the harness cannot be gamed.
- **Bounded context.** Only the compact reflection + the current failure record carry across iterations. Full transcripts are never accumulated (`specclaw-build-context --failure-record --reflection`).
- **Whole-change re-verify each turn.** Every iteration re-runs all four gates over the entire change, catching cross-gate regressions — not just the one gate that was red.
- **Goal-driven execution.** The loop is the explicit goal-check loop of **Rule 4 (Goal-Driven Execution)** in `references/agent-guardrails.md`: each gate is a success criterion the loop iterates against, and spec acceptance criteria (checked by `/specclaw:verify`) are the ground truth.

## Relationship to build / verify / pr

The loop is **default-on** (`loop.enabled: true`). It wraps the existing phases rather than replacing them: `/specclaw:build` produces the first implementation, `/specclaw:verify` writes the reports the `verify`/`review` gates read, and `/specclaw:pr` pushes the branch the CI outer loop (Step 3) polls. With `loop.enabled: false`, run `/specclaw:build` and `/specclaw:verify` as single-pass phases exactly as before.
