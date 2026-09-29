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

**Jira sync** (if `jira.enabled: true`): `specclaw-jira-issue transition .specclaw <change> build` so the card moves to In Progress as the build starts, rather than sitting in the backlog until archive.

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

## Step 2.5 — Teaching gate (if `teach.enabled: true`)

Run `specclaw-teach .specclaw status`. If `enabled` and `gate_builds` are true, **stop here before
spawning any agent** and gate the first wave — see the Teaching mode section at the end of this skill
for the gate format. Re-gate at the top of each subsequent wave.

This step exists at this position on purpose: tasks must be parsed (Step 2) before you can gate on
them, and the gate is worthless after Step 3 has already built everything.

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

**b'.** Compute the memory-aware concurrency ceiling for this wave:
```bash
specclaw-parallel-budget .specclaw
```
Prints one integer — `min(parallel_tasks, memory_budget)`. Use it as the concurrency ceiling for THIS wave in place of raw `parallel_tasks`. When no `build.memory` config is present it returns `parallel_tasks` unchanged (opt-in — no behavior change).

**c.** For each task in the wave (up to the memory-aware budget from `specclaw-parallel-budget` (≤ `parallel_tasks`) concurrent):

1. Mark in-progress:
   ```bash
   specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> in_progress
   ```
2. Build the agent context payload:
   ```bash
   specclaw-build-context .specclaw <change> <TASK_ID>
   ```
3. Spawn a coding agent with that payload as the task. Run independent tasks in parallel up to the memory-aware budget from step **b'** (≤ `parallel_tasks`). Calibrate delegation: spawn agents for tasks that are parallel, isolated, or independent workstreams; for a trivial sequential edit where spawning costs more than doing, apply the change directly and record it against the task as usual.

   **Dynamic subagents (`build.dynamic_agents.enabled: true`):** instead of the generic coder with `models.coding`, synthesize a bespoke agent per task:
   1. Synthesize the scaffold:
      ```bash
      specclaw-build synth-agent .specclaw <change> <TASK_ID>
      ```
      Returns JSON `{kind, tier, role, tools, model, downgrade, sig, system_prompt}` (and caches it under `.specclaw/changes/<change>/agents/<TASK_ID>.json` when `cache: true`). A cache hit with an unchanged task signature is reused.
   2. **LLM-fill (hybrid):** replace the `{{SPEC_DESIGN_SLICE}}` marker in `system_prompt` with the task's relevant slice of `spec.md` / `design.md` (the acceptance criteria this task serves + the design decisions touching its files). Write the enriched spec back to `agents/<TASK_ID>.json`.
   3. **Dispatch:** spawn the agent with `system_prompt` as its system prompt, the `specclaw-build-context` output as its task, restricted to the synthesized `tools`, at the synthesized `model`.
   4. **Provenance:** record the task's `role` and `model` in `status.md`'s Agent Runs table.
   5. **Fallback:** if synthesis fails (helper error, malformed JSON), fall back to the generic coder with `models.coding` for that task and continue — never block the build.

   When `build.dynamic_agents.enabled: false` (default), skip all of the above and use the generic coder exactly as before — no synthesis, no `agents/` directory.

**c'.** **Stub tasks** — only when `spec.md` has a `## Bypassed Dependencies` section. For a task implementing an `ST-###` stub, add `$CLAUDE_PLUGIN_ROOT/references/stub-discipline.md` to that agent's context alongside the usual payload, and hold it to two things:

- **The hard rule: dev/test scope only.** The stub must be *structurally unreachable* from any production code path — a test-only source set, a dev-profile-only registration, a flag that is off by default in production rather than by assertion. Use whatever mechanism the repo already has; inventing a new isolation mechanism for a stub is itself the signal to stop and report. "Unlikely to be hit" is not scoping. A stub that can serve a real user is not a bypass, it is a fabricated response in production.
- **The stub must match the strategy the human chose.** If implementation shows the chosen strategy is wrong, stop and report it — that is a decision to hand back, not one to make. Never widen a stub's reach to make a test pass.

After the task lands, complete its registry entry with the real citation:

```bash
specclaw-bf-rebuild-collect stub-update .specclaw ST-### \
  --fakes "<what it concretely does instead of the real thing>" \
  --implementation "<path/File.ext:88> — <how it is dev/test scoped>"
```

Both are citations, not summaries: a reviewer must be able to jump to that `file:line` and see the claim is true. **Never add a stub that has no registry entry** — an unregistered stub is invisible to `/specclaw:bf-replay`'s taint stamping, so a report will later claim a clean PASS that was earned against fabricated behaviour.

**c''.** **Split changes** — only when `spec.md` has a `## Item Split` or `## Resumed From Split` section. Add `$CLAUDE_PLUGIN_ROOT/references/split-discipline.md` to the relevant agents' context, and hold the build to three things:

- **Never build deferred scope.** The spec's now-slice is the whole job. If a task cannot be completed without the deferred scope, **stop and report** — that means the partition is wrong, which is a decision to hand back, not a boundary to move. Widening the slice to make a test pass is the same failure as widening a stub's reach.
- **On a resume, never rebuild what the earlier slice already built.** Read the `IS-###`'s `Implemented now`, `Rules implemented` and `Change`/`Evidence` fields and treat that code as existing — you are integrating with it. Criteria labelled `[already built: IS-###]` are out of scope and must not be re-implemented.
- **Complete the entry's evidence fields** once the change lands:

```bash
specclaw-bf-rebuild-collect split-update .specclaw IS-### \
  --change "<change-name>" --evidence "<PR url or merge sha>"
```

**Never flip a split's Status yourself.** `READY-TO-RESUME` is computed by bash during `/specclaw:bf-rebuild-plan --refresh` from the blocked-until items' own declared `BUILT:` notes; `COMPLETE` requires a clean `/specclaw:bf-replay --item BL-###` run to cite, and `split-update` refuses `COMPLETE` straight from `ACTIVE`.

**c3. Timing (change 028).** Open a span per wave before dispatching it, and one per task as it is
dispatched — **every call ends in `|| true`**, because a build that fails because its stopwatch broke
is strictly worse than the unaccountability this measures:

```bash
specclaw-timer start .specclaw <change> "W<N>" --kind wave --label "wave <N>" || true
specclaw-timer start .specclaw <change> "<TASK_ID>" --kind task \
  --label "<title>" --parent "W<N>" --model "<model>" --attempt "<n>" || true
```

While the wave runs, print a progress line on the heartbeat interval
(`timing.heartbeat_seconds`, default 60):

```bash
specclaw-progress .specclaw <change> --phase build
```

That line is the whole point: it names the **active step**, its **elapsed time** and the **current
bottleneck**, so an operator or a watchdog can judge liveness instead of guessing. A pane emitting it
every 60s is never "no reply for 13 min" — which is the teardown this exists to prevent.

**d.** Wait for all agents in the wave to complete.

**e.** For each succeeded agent:
   0. **Evidence before done — always, and not configurable.** Write the agent's report to
      `.specclaw/changes/<change>/reports/<TASK_ID>.md` and check it:

      ```bash
      specclaw-build check-report .specclaw/changes/<change>/reports/<TASK_ID>.md --task <TASK_ID>
      ```

      **Exit 1 means the task is `failed`, not `complete`** — reason `no-verification-evidence` — and
      it goes down path **f** below with the printed line as the failure summary; the retry restates
      the footer requirement. An agent that reports "implemented and tested" having run nothing is
      the single most common way a build ends green and broken, and this is the only place a script
      can catch it. Do not paraphrase the check's verdict, and never mark a task complete on a report
      it rejected.
   1. Mark complete: `specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> complete`. If the task previously failed, run `specclaw-log-error .specclaw <change> --resolve <TASK_ID>`.
   2. Commit: `specclaw-build commit .specclaw <change> <TASK_ID> "<title>" <files...>`.
   2b. **Per-task review — only when `build.task_review` is `spec` or `full`** (it ships `off`, in
      which case skip this entirely and build behaves exactly as it did before):

      ```bash
      specclaw-build review-package .specclaw <change> <TASK_ID>
      ```

      Spawn the existing `code-reviewer` agent on `models.review` — **always `models.review`, never
      the `dynamic_agents` ladder**: the ladder sizes implementation difficulty, and reading one
      task's diff is not that work. Give it the task-scoped prompt from
      `$CLAUDE_PLUGIN_ROOT/references/agent-prompts.md`, and tell it the mode (`spec` = compliance
      only, `full` = compliance then quality).

      Read the verdict token it ends with and act on it mechanically:

      | Verdict | Do |
      |---|---|
      | `PASS` / `NOTE` | record it in the Agent Runs `Review` column; continue |
      | `WARN` | record `WARN(n)`; the findings stay in `reviews/<TASK_ID>.md`; continue |
      | `BLOCK` | mark the task **failed**, write the findings into `errors.md`, and send it down path **f** |

      **A `BLOCK` retry shares the task's normal retry budget.** It does not get one of its own — a
      task that fails review and a task that fails its tests are both "this task is not done", and
      two counters would let a task alternate between them and exhaust neither.
   3. Close the span: `specclaw-timer stop .specclaw <change> <TASK_ID> --status ok || true`.
   4. Notify: `✅ Task Complete: <TASK_ID> — <title>`.

**f.** For each failed agent:
   0. Close the span: `specclaw-timer stop .specclaw <change> <TASK_ID> --status fail || true`.
   1. Mark failed: `specclaw-update-task-status .specclaw/changes/<change>/tasks.md <TASK_ID> failed`.
   2. Log: `specclaw-log-error .specclaw <change> <TASK_ID> <wave> <agent_label> "<summary>"`.
   3. Update status.md with the failure reason.
   4. Notify: `❌ Task Failed: <TASK_ID> — <title>`.
   5. Mark dependent tasks in later waves as skipped/failed.
   6. **GitHub sync** (if enabled): `specclaw-gh-sync comment .specclaw <change> "❌ Task <TASK_ID> failed: <summary>"`.
   7. **Azure Boards sync** (if `azdo.boards.sync: true`): `specclaw-azdo-issue comment .specclaw <change> "❌ Task <TASK_ID> failed: <summary>"`.
   8. **Jira sync** (if `jira.enabled: true`): `specclaw-jira-issue comment .specclaw <change> "❌ Task <TASK_ID> failed: <summary>"`.

**g.** GitHub sync (if enabled): `specclaw-gh-sync update .specclaw <change>` to refresh task checkboxes.
**g'.** Azure Boards sync (if `azdo.boards.sync: true`): `specclaw-azdo-issue update .specclaw <change>` to refresh the Work Item description with the latest task checklist; optionally `specclaw-azdo-issue comment .specclaw <change> "Wave <N> complete: <X>/<total> tasks done"`.
**g''.** Jira sync (if `jira.enabled: true`): `specclaw-jira-issue update .specclaw <change>` to refresh the issue description with the latest task checklist. The card is already In Progress from Step 1 — do not re-transition per wave.

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

**c2. Size drift — report it, never fix it.** When a task's `files:` list grew past the file map in
`spec.md`, or a task failed with a `design_gap` learning, the change may have outgrown its declared
size. Say so, name the command, and **stop there**:

```
⚠ size-upgrade-needed — <change> is `bounded` but T5 touched 4 files outside the spec's map.
  specclaw-set-size .specclaw <change> architectural --reason "<why>"
```

Detecting the drift is mechanical; acting on it is not. **An upgrade changes what the operator
approved**, and a bounded → architectural upgrade makes `design.md` required again, so the next
`validate-change` will stop until `/specclaw:plan --design-only` fills it. That is a decision to hand
back, exactly as `reconcile --fix` declines downgrades and `party.block` leaves the verdict advisory.
Never call `specclaw-set-size` on the operator's behalf, and never downgrade — the ratchet refuses it
by name anyway.

**d.** Pattern scan: `specclaw-detect-patterns .specclaw scan <change>`.

**e.** If any pattern has recurrence ≥ 3, alert the user.

## Step 5b — Render the timeline

```bash
specclaw-timer stop   .specclaw <change> "W<N>" --status ok || true
specclaw-timer report .specclaw <change> --baseline --write || true
```

`--write` installs `timeline.md` in the change dir, where `specclaw-pr` quotes it into the PR body's
**Time accounting** section. Fill the `Agent Runs` table from the ledger rather than from memory:

```bash
specclaw-timer agent-runs .specclaw <change>
```

That table's `Duration` column has existed since `templates/status.md` was written and no script has
ever filled it.

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
**Branch:** specclaw/<change> → pushed (not merged)
**Next:** /specclaw:verify, then /specclaw:pr
```

**Build never creates or announces a pull request.** It ends at "branch pushed". Every guarantee in
`specclaw-pr` — the artifact staging, the hard constraint that the planning trail is committed, the
staged-files gate — is unreachable when a PR is opened any other way, and a build summary that names
a PR URL is how a hand-rolled `gh pr create` gets normalised. If a PR is wanted, run
`/specclaw:verify` and then `/specclaw:pr`.

## Key Principles

- **Fresh context always** — each agent gets ONLY what `specclaw-build-context` produces. No stale context.
- **Parallel within waves, sequential across waves.**
- **Fail-fast on dependencies** — if a task fails, all dependents are immediately marked failed.
- **Agent guardrails** — every coding agent is auto-prepended four behavioral rules (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution), vendored verbatim from Andrej Karpathy's CLAUDE.md. See `references/agent-guardrails.md`. Injection happens inside `specclaw-build-context`; no config flag.
- **Loop-aware** — when `loop.enabled: true` (the default), this build is one turn of the autonomous loop driven by `/specclaw:loop`, which re-runs verify+review and fixes the smallest diff until every gate is green or a guardrail halts. Build produces the first implementation; the loop remediates it. When `loop.enabled: false`, build behaves single-pass exactly as documented above — no loop, no extra files.

## Teaching mode (if `teach.enabled: true`)

Check with `specclaw-teach .specclaw status`. When enabled with `gate_builds: true`, before each wave that uses a technology the learner profile rates **a** or **b**:

1. **Gate** — state where they are in one line, offer a 3-minute concept brief, offer a quick PoC or straight-in, and ask for the **one decision** this wave needs (with a recommendation and what it costs). Then stop.
2. **Build** at full speed with no narration. Fix your own bugs — do not walk the user through debugging.
3. **After the wave**, give exactly **one** verify command, with what they should see and what it means.
4. Log briefs given: `specclaw-teach .specclaw <change> log brief "<topic and key points>"`.

Generate briefs from the recipe in `references/teaching-mode.md` — there is deliberately no cheatsheet library. Cache each at `.specclaw/knowledge/briefs/<topic>.md`. Never ask the user to type code "to learn"; ask them to decide, predict, or explain.
