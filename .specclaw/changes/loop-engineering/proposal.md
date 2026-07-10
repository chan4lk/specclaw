# Proposal: Loop Engineering — Autonomous Build→Verify→Review Loop

**Created:** 2026-07-10
**Status:** 🟡 Draft

## Problem

The specclaw lifecycle stops being autonomous exactly where it matters most. `/specclaw:build` runs the tasks and `/specclaw:verify` checks them, but when verify returns **FAIL** or **PARTIAL**, remediation is **manual**: the `verify` skill's "Remediation" section only *suggests* the user re-plan or hand-fix, then re-verify. A human has to read the report, decide what to fix, drive the next build, and re-run verify — every iteration.

That means a change is never truly "done" by the tool. Tests can be red, code review can raise BLOCK findings, and the lifecycle still hands control back to the operator to babysit the fix-verify cycle. For anything non-trivial this is several manual round-trips.

We want the build→verify→review steps to **run as a loop** that closes on its own: keep fixing and re-verifying until the change is actually complete — all tasks done, tests green, code review clean — with hard guardrails so it never thrashes forever.

## Proposed Solution

Add a **loop controller** that wraps build→verify→(code-review) into an autonomous iterate-until-done cycle, grounded in the *evaluator-optimizer* agent pattern (Anthropic, *Building Effective Agents*) with *Reflexion*-style feedback (Shinn et al.).

**Loop shape** (owned by a controller script + a new `/specclaw:loop` skill, not by prompt text):

```
until all_gates_green:
    build/fix           # optimizer: minimal-diff remediation
    run gates           # evaluator: tests, lint, verify ACs, code review
    if regressed OR duplicate-failure×N OR no-progress OR cap-hit:
        escalate + preserve state   # commit partial, keep worktree, log trail
        stop
    else:
        reflect → feed structured failure forward
```

**Two-tier loop.** The loop runs in two nested stages:
- **Inner loop (local, default-on):** build → verify → code-review → local test/lint/typecheck. Fast (seconds–minutes), all in-session.
- **Outer loop (CI, opt-in via `loop.ci_gate`):** after the PR branch is pushed, poll the remote pipeline (GitHub Actions or Azure Pipelines). On red, pull the failed-run logs, feed them back as a structured failure record, fix, push, re-poll — until checks are green. Reuses the already-wired `gh` / `az` CLIs (`gh pr checks --watch`, `gh run view --log-failed`; `az pipelines runs`), so it lives inside specclaw — **not** an MCD-only workflow. MCD's scheduling layer (ScheduleWakeup / cron) is only needed for *fully detached* runs across long CI waits; in-session it is a blocking poll.

**Done = mechanical gate, all-green simultaneously:**
1. All tasks in `tasks.md` complete.
2. Configured `test_command` / lint / typecheck exit clean (local).
3. `/specclaw:verify` verdict = **PASS** (all spec acceptance criteria met).
4. Code review returns **zero BLOCK** findings.
5. **(If `loop.ci_gate: true`)** all remote PR/merge checks (GitHub Actions / Azure Pipelines) green.

**Feedback routing (Reflexion):** each failed iteration produces a *structured failure record* — which gate failed, specific errors, implicated files/lines, and whether the failure is **new or a repeat** — plus a compact verbal reflection. Only that record + reflection carry forward (not full transcripts), keeping context lean. Remediation agents are instructed to make the **smallest diff** that turns the failing gate green.

**Anti-thrash guardrails (enforced in the controller, not the prompt):**
- **Iteration ceiling** (`loop.max_iterations`, default e.g. 5) + optional wall-clock / spend cap that aborts *before* the next paid agent call.
- **No-progress detection:** hash the diff + failure signature each turn; N identical/empty turns → halt.
- **Oscillation detection:** track failure signatures; Nth identical failure and A→B→A flip-flops route to escalation, not another retry.
- **Regression tripwire:** if the count of passing gates *drops* vs. the prior turn, stop — agent is going backwards.
- **Escalate + preserve:** on any halt condition, commit partial work, keep the git worktree intact, log the reflection trail, notify the operator with a clear "why it stopped."

**Reward-hacking defense (critical):** agents must not be able to fake a pass. Run tests from a **read-only / pinned copy** the fix agent can't edit; **diff the test files** each iteration and **reject** any change that touches the test harness within a fix turn; require the remediation diff to modify source, not the scorer.

## Scope

- New `specclaw-loop` controller script (`bin/`) owning gate evaluation, progress/regression/oscillation detection, and halt/escalate decisions.
- New `/specclaw:loop` skill orchestrating build → verify → code-review → reflect → re-fix.
- **Outer CI-gate stage:** poll GitHub Actions / Azure Pipelines after PR push, pull failed-run logs, feed back, fix, push, re-poll until green. Reuses `gh` / `az`. Opt-in via `loop.ci_gate`.
- Structured failure-record + reflection format fed into remediation context (extend `specclaw-build-context`).
- Config keys under `loop:` in `config.yaml` (`enabled` default **true**, `max_iterations`, caps, `protect_tests`, `ci_gate`, `ci_max_iterations`).
- Reward-hacking guard: test-file diff rejection + read-only test execution.
- Escalation + state-preservation path (partial commit, worktree kept, notification).
- Wire into existing build/verify/pr skills so the loop runs by default (`loop.enabled: true`).

### Out of Scope
- Rewriting the existing single-pass build or verify engines — the loop *reuses* them.
- Multi-change / cross-change orchestration (loop is per-change).
- Model fine-tuning or training-based self-correction.
- **Fully detached / unattended CI looping across long waits** — that needs MCD scheduling (ScheduleWakeup / cron) and is a separate integration. This proposal covers in-session CI polling only.
- Defining or authoring the CI pipelines themselves — the loop only *consumes* their pass/fail signal.

## Impact

- **Files affected:** ~8–12 (estimated) — 1 new controller script, 1 new skill, edits to build/verify/pr skills, `specclaw-build-context`, config schema, plugin CLAUDE.md, version bumps.
- **Complexity:** medium–large
- **Risk:** medium — autonomous loop spends tokens and mutates code unattended; guardrails (caps, regression tripwire, reward-hack defense) are the primary risk mitigation and must be solid before enabling by default.

## Decisions

- **Default-on.** `loop.enabled: true` by default. Guardrails (caps, regression tripwire, reward-hack defense) must be solid since it runs unattended out of the box.
- **CI gate is in scope**, as an opt-in outer loop tier reusing `gh` / `az`. Not MCD-only; MCD only needed for detached long-wait runs (out of scope).
- **Iteration caps:** inner (local) loop `max_iterations: 5`; CI outer loop `ci_max_iterations: 3` (each cycle = full pipeline, expensive).
- **Gate granularity:** re-verify the **whole change** each turn (not per-failing-gate scope) — simpler, avoids masking cross-gate regressions.
- **Reflection trail persisted** to `.specclaw/changes/<change>/loop-log.md` — audit trail + enables resume.

## Open Questions

_Resolved. Ready to plan._

Deferred to design (non-blocking):
- Token/wall-clock spend ceiling in addition to iteration count — add now or later.
- Require `git.strategy: worktree-per-change` when loop enabled.
- CI poll cadence & per-cycle timeout for hung pipelines (default ~20 min wall-clock).

---

**To proceed:** Review this proposal and approve to begin planning.
