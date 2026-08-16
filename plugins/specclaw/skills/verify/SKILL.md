---
description: Validate that the implementation satisfies the spec's acceptance criteria. Runs the configured test/lint/build commands, evaluates against spec.md, and produces verify-report.md. Required before /specclaw:pr. Run after all tasks in /specclaw:build are complete.
---

# specclaw verify

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Validate that the implementation satisfies the spec.

## Step 0 — Validate

```bash
specclaw-validate-change .specclaw <change> verify
```

If it fails (tasks not all complete), report and stop.

**If `.specclaw/context.md` exists**, read it before evaluating — the verifier must check that the implementation respects the project's coding rules, patterns, and constraints documented there, in addition to the spec's acceptance criteria.

## Step 0.5 — Prediction (if `teach.enabled` and `depth: full`)

Run `specclaw-teach .specclaw status`. If `depth` is `full`, ask the user to predict the headline
numbers **before** Step 1 runs anything — a prediction offered after the results are on screen is
worthless. See the Teaching mode section at the end of this skill.

## Step 1 — Collect evidence

```bash
specclaw-verify collect .specclaw <change>
```

Gathers acceptance criteria from `spec.md`, current contents of changed files, and configured lint/build/test command results — run in that order — followed by the e2e tier when configured.

### E2E tier (`build.e2e_command` + `verify.e2e`)

`build.e2e_command` is the slow tier (browser/e2e); `build.test_command` stays the fast tier. `verify.e2e` decides when the slow tier runs:

| Policy | Behaviour |
|--------|-----------|
| `last` (default) | Run e2e only after `lint_command`, `build_command` and `test_command` all pass. An unset fast-tier command is vacuously passing. |
| `skip` | Never run e2e. |
| `always` | Run e2e even when an earlier gate failed. |

An absent `verify.e2e` means `last`; an unrecognised value warns on stderr and falls back to `last`.

When the e2e command does run, `collect` brackets it: it takes a browser slot (`specclaw-browser-lock acquire`), passes the command through `specclaw-browser-lock wrap` — which adds `--workers=1` for Playwright, one sequential `--project=` invocation per `verify.playwright.projects` entry, and a `MemoryMax=<verify.playwright.max_memory_mb>M` scope when `systemd-run` is usable — runs the wrapped string, then releases the slot. The slot is released even when the command fails or the run is interrupted. When `systemd-run` is unusable, `wrap` warns and the command runs uncapped.

When any of these keys is present, `collect` adds three fields to the payload:

- **`e2e_output`** — the e2e command's capped output, or an explicit reason string when it did not run.
- **`e2e_state`** — one of `passed`, `failed`, `skipped_policy`, `skipped_gate_failure`, `not_configured`.
- **`e2e_memory_limited`** — `true` only when the e2e command exited `137` (SIGKILL) **while a memory cap was actually applied**. An exit `137` with no cap in force (`systemd-run` unusable, or no browser-lock) leaves this `false`, because the kill cannot be attributed to a specclaw cap.

With none of the keys present, the payload is unchanged from before the e2e tier existed.

**Report a skip as a skip — never as a pass.** `e2e_state` is the authority, not `e2e_output`:

- `passed` is the *only* state that may be reported as e2e passing.
- `skipped_policy`, `skipped_gate_failure` and `not_configured` mean **e2e evidence does not exist**. Say so explicitly in `verify-report.md` (e.g. "E2E: skipped — `verify.e2e=last`, lint gate failed; no e2e evidence"), and do not mark an acceptance criterion that depends on e2e evidence as met. If an AC can only be proven by the e2e suite, a skipped e2e makes that AC unverified, which caps the verdict at PARTIAL.
- `e2e_memory_limited: true` must be reported as **the memory limit was exceeded**, naming the cap that `e2e_output` quotes (e.g. "E2E: memory limit exceeded — killed by SIGKILL under cap 4096M"). Never call it a flaky, transient or generic test failure, and never suggest a re-run as the fix: raise `verify.playwright.max_memory_mb`, cut `verify.playwright.max_browsers`, or split `verify.playwright.projects`.
- `e2e_memory_limited: false` with `e2e_state: failed` is an ordinary failure — report it from `e2e_output` on its own terms. An exit `137` here means the process was killed with no specclaw cap in force (host OOM killer or an external kill); say that, and do not name a cap.

## Step 2 — Build verify context

```bash
specclaw-verify-context .specclaw <change>
```

Constructs the verification agent's context payload from the evidence and the Verify Agent prompt template (in `$CLAUDE_PLUGIN_ROOT/references/agent-prompts.md`).

## Step 3 — Spawn verify agent

Spawn a verification agent using the context payload from Step 2. Use the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`). Wait for completion.

## Step 3.5 — Code review (conditional)

Read `workflow.code_review` from `.specclaw/config.yaml`. If `false` or not set, skip this step entirely (no output, no error).

If `true`:
1. Read `.specclaw/changes/<change>/design.md` — use empty string if absent.
2. Read `.specclaw/changes/<change>/tasks.md` — use empty string if absent.
3. Spawn the `code-reviewer` agent using the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-6`). Pass: changed files content (from Step 1), spec content, design content, tasks content, change name.
4. Write the agent's output to `.specclaw/changes/<change>/review-report.md` (overwrite if exists).
5. Extract the verdict line from `review-report.md` and append a one-line summary to the verify-report that will be written in Step 4:
   `**Code Review:** <verdict> — <N findings: X BLOCK, Y WARN, Z NOTE>`

## Step 4 — Save report

Save the agent's output as `.specclaw/changes/<change>/verify-report.md`. If Step 3.5 ran, append the code review summary line from Step 3.5 to the end of this report.

## Step 5 — Update status

Extract the verdict (PASS, FAIL, or PARTIAL) from the report, then:

```bash
specclaw-verify update-status .specclaw <change> <verdict>
specclaw-update-status .specclaw
```

## Step 6 — External tracker sync (if enabled)

GitHub:
```bash
specclaw-gh-sync comment .specclaw <change> "<verdict summary>"
```

Azure Boards (if `azdo.boards.sync: true`):
```bash
specclaw-azdo-issue comment .specclaw <change> "Verify <verdict>: <verdict summary>"
```

## Step 7 — Notify

Send verification results via the configured notification channel.

## Verifier guardrails

`/specclaw:verify` is the explicit goal-check loop called out by **Rule 4 (Goal-Driven Execution)** in `references/agent-guardrails.md`: each acceptance criterion in `spec.md` is a success criterion the verify agent loops against. Tests are one form of goal-check, but ACs are the ground truth.

## Auto-verify

When `automation.auto_verify: true`, `/specclaw:build` automatically triggers verification on success.

## Remediation

When `loop.enabled: true` (the default), remediation is automated by `/specclaw:loop`: the failed gates are fed back as a structured failure record, a fix agent makes the smallest diff to turn them green, and the whole change is re-verified — repeating until PASS or a guardrail (cap / no-progress / regression / oscillation) halts and escalates.

When `loop.enabled: false`, remediation is manual. If verdict is FAIL or PARTIAL:
1. List the failed acceptance criteria.
2. Suggest creating remediation tasks targeting the gaps.
3. The user can re-plan just the failed criteria or manually fix and re-verify.

## Teaching mode (if `teach.enabled: true`)

Check with `specclaw-teach .specclaw status`. When `depth: full`, ask for a **prediction before revealing any number**:

> "Sustained 150 rps across 4 shards — what p95 do you expect?"

Then compare explicitly and log it:

```bash
specclaw-teach .specclaw <change> log prediction "Predicted <x>; measured <y>; gap = <cause>"
```

A wrong prediction is the most valuable event in the change — it marks exactly where the user's mental model diverges from the system. It costs fifteen seconds; never skip it to save time.
