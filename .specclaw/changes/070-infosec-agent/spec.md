# Spec: An InfoSec agent for SpecClaw projects: before, during and after the build, with evals

**Change:** 070-infosec-agent
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
- **FR-8** The agent reads a `mode` (`plan`, `build` or `verify`) from its prompt. In `plan` mode it reads
  `proposal.md` and writes `.specclaw/changes/<change>/security-requirements.md`: a Threat Model section and
  numbered requirements `SR-1`, `SR-2`, ... each checkable by a test or a code read. In `build` mode it reviews one
  task's diff and writes `.specclaw/changes/<change>/security/<T>.md` with the usual verdict. In `verify` mode it
  behaves as in FR-2 to FR-4 and also reports each `SR-n` as met or not met.
- **FR-9** `references/full/plan.md` has a step that, only when `workflow.security_review` is `true`, spawns the
  agent in `plan` mode before `spec.md` is written; the planner turns each `SR-n` into an acceptance criterion in
  `spec.md` and a task where one is needed.
- **FR-10** `references/full/build.md` tells builders to read `security-requirements.md` when it exists, and has a
  step beside the per-task review (2b) that, only when `workflow.security_review` is `true` and the task touches an
  entry point (route, form, upload, webhook, CLI arg or env var read, or an auth flow), runs
  `specclaw-build review-package` and spawns the agent in `build` mode. A BLOCK is sent back to the task's agent once;
  if it is still BLOCK it is written to `follow-ups.md` and the build continues (advisory).
- **FR-11** `references/full/verify.md` Step 3.52 passes `security-requirements.md` (when present) and the
  per-task `security/` notes to the agent, and the verify-report line counts unmet `SR-n`.
- **FR-12** `plugins/specclaw/tests/evals/infosec/<case>/` holds `vulnerable.<ext>`, `fixed.<ext>` and `expect` (one
  line `rule: <review-pack id>|<preset keyword>`, e.g. `rule: B16|Codes`) for at least 8 cases taken from the Shannon findings: secret or code in a response,
  dev bypass flag, session surviving logout, account enumeration, uncapped code attempts, URL allowlist by
  substring, rate limit keyed on `X-Forwarded-For`, secret in a committed change record.
- **FR-13** `plugins/specclaw/tests/run-infosec-evals.sh` runs the agent on every sample (`SPECCLAW_INFOSEC_REPS`
  reps, default 3) and prints the catch rate on `vulnerable` (any finding that cites the expected rule id or keyword) and the
  false-alarm rate on `fixed` (any BLOCK), with the model. It skips with exit 0 unless `SPECCLAW_INFOSEC_EVALS=1`,
  and runs nightly in its own workflow.
- **FR-14** A structural test, registered in `ci.yml`, checks every case has both samples and a non-empty `expect`
  naming a rule id that exists in a review pack.

## Non-Functional Requirements

- Off by default: with `workflow.security_review` unset or `false`, verify behaves exactly as before.
- `code-reviewer.md` and the loop gates are not changed.
- Plan, build and verify spawns all sit behind the one `workflow.security_review` flag; the evals never run in the
  per-push CI (only their structural test does), because they spend model calls.

## Acceptance Criteria

- [ ] **AC-1** — GIVEN `agents/infosec-reviewer.md`, WHEN read, THEN it has valid front matter and names the four
  steps, the auth-flow questions and the five SpecClaw-specific checks.
- [ ] **AC-2** — GIVEN `templates/config.yaml`, WHEN read, THEN `workflow.security_review` is `false`.
- [ ] **AC-3** — GIVEN `references/full/verify.md`, WHEN read, THEN a step spawns `infosec-reviewer` only when
  `workflow.security_review` is `true`, and states it is advisory.
- [ ] **AC-4** — GIVEN the agent file with any one required check or step deleted, WHEN the test runs, THEN it
  fails and names the missing item.
- [ ] **AC-5** — GIVEN the new test, WHEN CI is read, THEN the suite is registered in `ci.yml`.

- [ ] **AC-6** — GIVEN the agent file, WHEN read, THEN it names the three modes and what each writes
  (`security-requirements.md` with `SR-n`, `security/<T>.md`, `security-report.md`).
- [ ] **AC-7** — GIVEN `references/full/plan.md`, WHEN read, THEN a step spawns the agent in `plan` mode only when
  `workflow.security_review` is `true`, before `spec.md`, and tells the planner to turn `SR-n` into acceptance criteria.
- [ ] **AC-8** — GIVEN `references/full/build.md`, WHEN read, THEN builders read `security-requirements.md` and a step
  reviews entry-point tasks only, in `build` mode, advisory, behind the flag.
- [ ] **AC-9** — GIVEN `references/full/verify.md` Step 3.52, WHEN read, THEN it passes `security-requirements.md`
  and the `security/` notes and counts unmet `SR-n`.
- [ ] **AC-10** — GIVEN `tests/evals/infosec/`, WHEN listed, THEN at least 8 cases each have `vulnerable`, `fixed`
  and `expect` naming an existing review-pack rule.
- [ ] **AC-11** — GIVEN one case's `fixed` sample or its `expect` deleted, WHEN the structural test runs, THEN it
  fails and names the case.
- [ ] **AC-12** — GIVEN `SPECCLAW_INFOSEC_EVALS` unset, WHEN `run-infosec-evals.sh` runs, THEN it prints a skip
  line and exits 0; GIVEN it is `1`, THEN it prints catch rate, false-alarm rate and the model.
- [ ] **AC-13** — GIVEN CI, WHEN read, THEN the structural test is in `ci.yml` and the evals have a nightly workflow.

## Edge Cases

1. `workflow.security_review` set but `workflow.code_review` false: the step still runs; the two flags are
   independent.
2. The lean verify flow does not run `code-reviewer` either, so it does not run this agent. Unchanged.
3. `workflow.security_review` true but the change has no entry points: `plan` mode writes a Threat Model that says so
   and no `SR-n`; `build` mode runs on no task; verify behaves as before.
4. `security-requirements.md` missing at build or verify (flag turned on mid-change): skip it silently, no failure.

## Approach

Write the agent in the shape of `code-reviewer.md`. Add the config key beside `code_review`, and a Step 3.52
to `references/full/verify.md` beside Step 3.5. The test is a bash file that greps required phrases from the
agent, the config and the verify step; a deleted-phrase mutant per required item proves it names what is missing.

The `mode` lives in the one agent file, not three agents: the method is the same, only the input and the output
file differ. The build step reuses `specclaw-build review-package` and sits next to 2b, so no new script is needed.
The evals copy the trigger-eval pattern (`run-trigger-tests.sh`): opt-in env var, reps, model recorded, nightly.

File map:
- `plugins/specclaw/agents/infosec-reviewer.md` — new, then the three modes
- `plugins/specclaw/templates/config.yaml` — add `security_review: false`
- `plugins/specclaw/references/full/verify.md` — add Step 3.52, then the `SR-n` check
- `plugins/specclaw/tests/run-infosec-reviewer-tests.sh` — new
- `.github/workflows/ci.yml` — register the suite
- `plugins/specclaw/references/full/plan.md` — add the `plan`-mode step
- `plugins/specclaw/references/full/build.md` — read `security-requirements.md`; add the entry-point review step
- `plugins/specclaw/tests/evals/infosec/` — new, 8 cases
- `plugins/specclaw/tests/run-infosec-evals.sh` — new, the runner
- `plugins/specclaw/tests/run-infosec-eval-cases-tests.sh` — new, the structural test
- `.github/workflows/infosec-evals.yml` — new, nightly
- version files — one patch bump (already done once for this branch; it stays the last commit)
