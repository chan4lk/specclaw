---
description: Validate that the implementation satisfies the spec's acceptance criteria. Runs the configured test/lint/build commands, evaluates against spec.md, and produces verify-report.md. Required before /specclaw:pr. Run after all tasks in /specclaw:build are complete.
disable-model-invocation: true
---

# specclaw verify

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

## Step 4 — Save report

Save the agent's output as `.specclaw/changes/<change>/verify-report.md`.

## Step 5 — Update status

Extract the verdict (PASS, FAIL, or PARTIAL) from the report, then:

```bash
specclaw-verify update-status .specclaw <change> <verdict>
specclaw-update-status .specclaw
```

## Step 6 — GitHub sync (if enabled)

```bash
specclaw-gh-sync comment .specclaw <change> "<verdict summary>"
```

## Step 7 — Notify

Send verification results via the configured notification channel.

## Auto-verify

When `automation.auto_verify: true`, `/specclaw:build` automatically triggers verification on success.

## Remediation

If verdict is FAIL or PARTIAL:
1. List the failed acceptance criteria.
2. Suggest creating remediation tasks targeting the gaps.
3. The user can re-plan just the failed criteria or manually fix and re-verify.
