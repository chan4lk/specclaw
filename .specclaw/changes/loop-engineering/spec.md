# Spec: Loop Engineering — Autonomous Build→Verify→Review Loop

**Change:** loop-engineering
**Created:** 2026-07-10
**Status:** 🟡 Draft

## Overview

Add an autonomous iterate-until-done loop around the existing build→verify→review phases. When a gate fails, the loop feeds a structured failure record back into a targeted fix, re-runs the whole change through all gates, and repeats until every gate is green — or a guardrail halts it and escalates to the operator. An optional outer tier extends the loop to remote CI (GitHub Actions / Azure Pipelines). Grounded in the evaluator-optimizer + Reflexion patterns.

## Requirements

### Functional Requirements

- **FR1 — Loop controller.** A new `specclaw-loop` script owns gate evaluation and all halt/continue decisions. The `/specclaw:loop` skill orchestrates: run gates → if all green, done → else reflect, fix, re-run.
- **FR2 — Local gate set.** Each iteration evaluates, over the *whole change*: (a) all tasks in `tasks.md` complete, (b) `test_command` / `lint_command` / `build_command` exit clean (skipped if unset), (c) `/specclaw:verify` verdict = PASS, (d) code review returns zero BLOCK findings. Done = all applicable gates green simultaneously.
- **FR3 — Structured failure feedback.** On any red gate, the controller emits a failure record: gate name, specific errors, implicated files/lines, and a new-vs-repeat flag (by failure signature). The fix agent receives this record + a compact reflection and is instructed to make the smallest diff that turns the failing gate green.
- **FR4 — Iteration caps.** Local loop stops after `loop.max_iterations` (default 5). CI outer loop stops after `loop.ci_max_iterations` (default 3). Cap check happens *before* spawning the next agent / triggering the next CI cycle.
- **FR5 — No-progress detection.** Each turn the controller records a signature = hash(diff) + failure-signature. If N consecutive turns produce an empty diff or the identical failure signature, the loop halts (`loop.no_progress_limit`, default 2).
- **FR6 — Regression tripwire.** The controller tracks the count of passing gates per turn. If passing count drops vs. the prior turn, the loop halts immediately (agent went backwards).
- **FR7 — Oscillation detection.** Failure signatures are tracked across turns; the Nth identical failure and A→B→A flip-flop patterns route to escalation rather than another retry.
- **FR8 — Escalate + preserve state.** On any halt condition, the controller commits partial work, keeps the git worktree intact, finalizes `loop-log.md`, and emits an operator notification explaining exactly why it stopped and the current gate status.
- **FR9 — Reward-hacking guard.** Within a fix turn the controller diffs the test files (paths under the configured test globs); if the fix agent modified any test file, that turn is rejected and counts as a failure. Tests run from a pinned/read-only reference so the harness itself cannot be gamed.
- **FR10 — Reflection trail.** A per-change `loop-log.md` records each iteration: turn number, gate results, failure signature, reflection, action taken, and the halt/continue decision. Enables audit and resume.
- **FR11 — CI outer loop (opt-in).** When `loop.ci_gate: true`, after the PR branch is pushed the controller polls remote checks (`gh pr checks` / `az pipelines runs`). On failure it pulls failed-run logs (`gh run view --log-failed`), feeds them back as a failure record, fixes, pushes, and re-polls until green or `ci_max_iterations` / CI wall-clock timeout is hit.
- **FR12 — Config-driven, default-on.** All behavior is controlled by a `loop:` block in `config.yaml`. `loop.enabled` defaults to **true**. Existing single-pass build/verify still works when `loop.enabled: false`.

### Non-Functional Requirements

- **NFR1 — Bash + coreutils + git only** for the controller script, matching all existing `bin/` scripts (`gh` / `az` for CI tier). No new runtime dependency.
- **NFR2 — Reuses existing engines.** The loop calls the existing `specclaw-build`, `specclaw-verify`, `code-reviewer` agent, and `specclaw-parse-tasks` — it does not reimplement them.
- **NFR3 — Bounded context.** Only the compact reflection + current failure record carry across iterations; full transcripts are not accumulated.
- **NFR4 — Backward compatible.** A change that never fails a gate behaves like today's single-pass flow (loop exits after iteration 1).

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — With `loop.enabled: true` and a change whose first build leaves a failing test, the loop performs at least one fix iteration and exits PASS once the test is fixed, without manual intervention.
- **AC2** — The loop exits after exactly `loop.max_iterations` iterations when gates never go green, and emits an escalation notification stating the unmet gates.
- **AC3** — When a fix turn produces an empty diff or repeats the identical failure signature `no_progress_limit` times, the loop halts and escalates (no further agent spawn).
- **AC4** — When the count of passing gates drops between turns, the loop halts immediately (regression tripwire) and escalates.
- **AC5** — If a fix agent modifies a test file within a fix turn, that turn is rejected and logged as a reward-hack guard trip; the test change is not counted as progress.
- **AC6** — `loop-log.md` exists after any loop run and contains one entry per iteration with gate results, signature, reflection, and decision.
- **AC7** — On any halt, partial work is committed and the worktree is left intact (verifiable via `git log` / worktree presence).
- **AC8** — With `loop.ci_gate: true`, after a push the loop polls CI, and on a red check pulls the failed log, performs a fix cycle, and re-polls; it stops at `ci_max_iterations` or CI timeout with escalation.
- **AC9** — With `loop.enabled: false`, build and verify behave exactly as before this change (no loop, no new files required).
- **AC10** — `specclaw-loop --help`, config schema, and plugin CLAUDE.md document the `loop:` block and the `/specclaw:loop` skill.

## Edge Cases

- No test/lint/build commands configured → those gates are treated as trivially green (not failures).
- `git.strategy: direct` (no worktree) → loop still runs; state-preservation commits to the current branch and warns that no isolated worktree exists.
- CI configured but no pipeline attached to the PR → `ci_gate` treats "no checks" as green after a short grace poll, with a logged warning (avoids infinite wait).
- Change already PASSing on entry → loop exits after iteration 1 with no fix.
- Hung CI pipeline → CI wall-clock timeout triggers a halt+escalate rather than blocking forever.
- Concurrent gate failures (e.g. test + review both red) → single failure record enumerates all red gates; fix agent addresses all, whole change re-verified next turn.

## Dependencies

- Existing `specclaw-build`, `specclaw-verify`, `specclaw-parse-tasks`, `specclaw-build-context`, `specclaw-update-status`.
- `code-reviewer` agent (from `code-reviewer-agent` change).
- `gh` / `az` CLIs for the opt-in CI tier only.

## Notes

- MCD scheduling (detached long-wait CI looping) is explicitly out of scope; CI polling here is in-session blocking.
- Reward-hacking defense (FR9) is the highest-risk correctness requirement given default-on operation — it must be verified thoroughly.
