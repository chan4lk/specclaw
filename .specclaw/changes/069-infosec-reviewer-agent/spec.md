# Spec: An InfoSec reviewer agent for SpecClaw projects

**Change:** 069-infosec-reviewer-agent
**Size:** bounded

## Functional Requirements

- **FR-1** `plugins/specclaw/agents/infosec-reviewer.md` exists with front matter (`name: infosec-reviewer`,
  `description`, `tools`, `model`) and a prompt in the same shape as `code-reviewer.md`.
- **FR-2** The prompt makes the agent work in four steps: model the threat (assets, entry points, trust
  boundaries), ask the STRIDE questions per entry point (plus six auth-flow questions for login, code, sign-up, reset, logout and session paths), check the stack rules, and check the SpecClaw-specific
  surface (secrets in records, prompt injection, credentials, shell-outs, supply chain).
- **FR-3** Every finding must quote code, give a one-line attack scenario and name the rule or check; a finding
  without them is dropped. Severities are `BLOCK`/`WARN`/`NOTE`; verdicts are `APPROVED`,
  `APPROVED_WITH_NOTES`, `CHANGES_REQUESTED`.
- **FR-4** The agent writes `.specclaw/changes/<change>/security-report.md`.
- **FR-5** `templates/config.yaml` has `workflow.security_review: false`, and `specclaw-init` keeps it false.
- **FR-6** `references/full/verify.md` has a step that spawns `infosec-reviewer` after `code-reviewer` only when
  `workflow.security_review` is `true`, writes `security-report.md`, and appends one summary line to the
  verify-report. It blocks nothing.
- **FR-7** A test checks FR-1, FR-2, FR-5 and FR-6, and is registered in CI.

## Non-Functional Requirements

- Off by default: with `workflow.security_review` unset or `false`, verify behaves exactly as before.
- `code-reviewer.md` and the loop gates are not changed.

## Acceptance Criteria

- [ ] **AC-1** — GIVEN `agents/infosec-reviewer.md`, WHEN read, THEN it has valid front matter and names the four
  steps, the auth-flow questions and the five SpecClaw-specific checks.
- [ ] **AC-2** — GIVEN `templates/config.yaml`, WHEN read, THEN `workflow.security_review` is `false`.
- [ ] **AC-3** — GIVEN `references/full/verify.md`, WHEN read, THEN a step spawns `infosec-reviewer` only when
  `workflow.security_review` is `true`, and states it is advisory.
- [ ] **AC-4** — GIVEN the agent file with any one required check or step deleted, WHEN the test runs, THEN it
  fails and names the missing item.
- [ ] **AC-5** — GIVEN the new test, WHEN CI is read, THEN the suite is registered in `ci.yml`.

## Edge Cases

1. `workflow.security_review` set but `workflow.code_review` false: the step still runs; the two flags are
   independent.
2. The lean verify flow does not run `code-reviewer` either, so it does not run this agent. Unchanged.

## Approach

Write the agent in the shape of `code-reviewer.md`. Add the config key beside `code_review`, and a Step 3.52
to `references/full/verify.md` beside Step 3.5. The test is a bash file that greps required phrases from the
agent, the config and the verify step; a deleted-phrase mutant per required item proves it names what is missing.

File map:
- `plugins/specclaw/agents/infosec-reviewer.md` — new
- `plugins/specclaw/templates/config.yaml` — add `security_review: false`
- `plugins/specclaw/references/full/verify.md` — add Step 3.52
- `plugins/specclaw/tests/run-infosec-reviewer-tests.sh` — new
- `.github/workflows/ci.yml` — register the suite
- version files — one patch bump
