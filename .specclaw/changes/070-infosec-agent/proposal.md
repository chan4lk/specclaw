# Proposal: An InfoSec agent for SpecClaw projects: before, during and after the build, with evals

**Created:** 2026-11-16
**Status:** ✅ Approved (revised 2026-11-17)

## Problem

`code-reviewer` checks ten things at verify and security is one line of it. The presets and the review rule packs
now carry specific security rules per stack, but no reviewer thinks about a change the way an information-security
engineer does: what is being protected, who can reach it, how it could be abused. And nothing looks at the risks
that come with building through SpecClaw itself: change records are committed to git and quote command output,
agents read issue and PR text, tokens sit in `.specclaw/.env`, and scripts build shell commands from change names.

The first version only reviews at verify, after the code is written. By then a missing session check or an open
redirect is rework, not a design choice. Pen-test reports (Shannon) keep finding the same flaws, and we want fewer of
them written at all. We also have no way to tell whether the agent catches them: it has never been scored on a
known-vulnerable sample.

## Proposed Solution

Add an `infosec-reviewer` subagent, `plugins/specclaw/agents/infosec-reviewer.md`, that works like an InfoSec
engineer who knows how SpecClaw works, and runs at three moments, not one. (The change folder is named
`070-infosec-agent` because the work is now wider than a reviewer.)

1. **Model the threat.** From the spec and the diff it lists the assets (data, credentials, accounts), the entry
   points (routes, forms, files, webhooks, CLI args, env vars) and the trust boundaries the change crosses.
2. **Think like an attacker.** For each entry point it asks the STRIDE questions and keeps only the ones the code
   actually allows. STRIDE is the method, not a checklist to recite. For auth paths (login, one-time code, sign-up,
   reset, logout, sessions) it also asks six fixed questions drawn from a real pen test: a code or secret in a response
   or a dev bypass, sessions surviving logout, account enumeration, uncapped code attempts, a URL allowlist checked by
   substring, and a rate limit keyed on a client-set header.
3. **Check the stack rules.** The preset Security rules for the change's stacks and the matching `specclaw-review`
   pack are the checklist. It does not re-list generic categories those rules already cover.
4. **Check the SpecClaw-specific surface:**
   - **Secrets in records:** a token or key in the diff or in any file under `.specclaw/changes/` (reports quote
     command output and are committed).
   - **Prompt injection:** issue, PR or doc text that a build agent reads and could be told to act on.
   - **Credentials:** `.specclaw/.env` and `config.yaml` tokens committed or logged; `.gitignore` missing them.
   - **Shell-outs:** scripts that build a shell command from a change name, branch or file path.
   - **Supply chain:** a new or changed dependency without a stated reason, or a lockfile not committed.

Every finding quotes the code, gives a one-line attack scenario (who does what and what they get), names the rule
or check it breaks, and carries a severity. A finding with no quoted code and no scenario is dropped.

It writes `security-report.md` with `BLOCK`/`WARN`/`NOTE` severities and the same verdict words as `code-reviewer`
(`APPROVED`, `APPROVED_WITH_NOTES`, `CHANGES_REQUESTED`), so existing tooling can read it.

Wiring: `/specclaw:verify` spawns it right after `code-reviewer` when `workflow.security_review` is `true`. It ships
`false`, the same one-release rollout `workflow.code_review` and `party.default` took. It is advisory: the verdict
goes into the verify report and blocks nothing.

### Three moments (added 2026-11-17)

The agent reads a `mode` from its prompt: `plan`, `build` or `verify`. The method above is the same; what it looks
at and what it writes differ.

1. **Before (plan).** When `workflow.security_review` is true, `plan` spawns it in `plan` mode on `proposal.md`. It
   threat-models the idea and writes `security-requirements.md`: assets, entry points and numbered `SR-n`
   requirements, each checkable. The planner turns each `SR-n` into an acceptance criterion in `spec.md` and a task
   where one is needed. Design flaws are caught while they are still a sentence.
2. **While (build).** Builders read `security-requirements.md` with the presets. After each task's commit that touches
   an entry point (route, form, upload, auth), the agent in `build` mode reviews that task's diff only (passed in, as
   in verify) and writes `security/<T>.md`. A BLOCK finding is fixed before the next task, one retry, then it
   goes to `follow-ups.md`.
3. **After (verify).** The existing Step 3.52, now a safety net: it also checks every `SR-n` was met.

### Evals (added 2026-11-17)

Cases under `plugins/specclaw/tests/evals/infosec/`. Each case has a vulnerable sample, a fixed sample and an `expect`
file naming the rule it should hit. First cases come from the Shannon findings (code in a response, dev bypass,
sessions surviving logout, account enumeration, uncapped code attempts, substring URL allowlist, rate limit keyed on
`X-Forwarded-For`, secrets in records): about 8. `run-infosec-evals.sh` runs the agent on each sample, several reps
like the trigger evals, and prints the **catch rate** on vulnerable samples and the **false-alarm rate** on fixed ones.
It is opt-in (`SPECCLAW_INFOSEC_EVALS=1`) and runs nightly, because it spends model calls. A cheap structural check
(every case has both samples and an `expect`) runs in `ci.yml` on every push.

## Scope

### In Scope
- `agents/infosec-reviewer.md`, the verify step that spawns it, and the `workflow.security_review` config key.
- A small test that the agent file and the config key are well formed, registered in CI.
- The `mode` input and plan/build outputs of the agent; the plan and build steps that spawn it; the `SR-n` check in verify.
- The eval cases, the runner, a nightly workflow and the structural test.
- One patch version bump.

### Out of Scope
- Gating the PR or the loop on its verdict (a follow-up once it has been measured).
- Running scanners or pen-test style probes (separate changes).
- A gate on the eval score (measure first, set a threshold later).
- Any change to `code-reviewer`.

## Impact

- **Size:** bounded (adds one agent file, one verify step, one config key, one test)
- **Files affected:** ~14 (estimated) plus the version files
- **Complexity:** medium
- **Risk:** low (off by default)

## Open Questions

- Should a `BLOCK` eventually block the PR, as `workflow.code_review_block` does? Left for a follow-up.
- Decided 2026-11-17: per-task review in build runs only on tasks that touch an entry point.
- Which model? Proposed `models.review`, the same as `code-reviewer`.
