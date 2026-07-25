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

When any of these keys is present, `collect` adds three fields to the payload:

- **`e2e_output`** — the e2e command's capped output, or an explicit reason string when it did not run.
- **`e2e_state`** — one of `passed`, `failed`, `skipped_policy`, `skipped_gate_failure`, `not_configured`.
- **`e2e_memory_limited`** — `true` when the e2e command was killed with SIGKILL (exit `137`), i.e. it exceeded its memory limit.

With none of the keys present, the payload is unchanged from before the e2e tier existed.

**Report a skip as a skip — never as a pass.** `e2e_state` is the authority, not `e2e_output`:

- `passed` is the *only* state that may be reported as e2e passing.
- `skipped_policy`, `skipped_gate_failure` and `not_configured` mean **e2e evidence does not exist**. Say so explicitly in `verify-report.md` (e.g. "E2E: skipped — `verify.e2e=last`, lint gate failed; no e2e evidence"), and do not mark an acceptance criterion that depends on e2e evidence as met. If an AC can only be proven by the e2e suite, a skipped e2e makes that AC unverified, which caps the verdict at PARTIAL.
- `e2e_memory_limited: true` must be reported as *the memory limit was exceeded*, never as a generic or flaky test failure.

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
