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

## Step 1 — Collect evidence

```bash
specclaw-verify collect .specclaw <change>
```

Gathers acceptance criteria from `spec.md`, current contents of changed files, and configured test/lint/build command results.

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

If verdict is FAIL or PARTIAL:
1. List the failed acceptance criteria.
2. Suggest creating remediation tasks targeting the gaps.
3. The user can re-plan just the failed criteria or manually fix and re-verify.
