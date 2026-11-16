# Proposal: An InfoSec reviewer agent for SpecClaw projects

**Created:** 2026-11-16
**Status:** 🟡 Draft

## Problem

`code-reviewer` checks ten things at verify and security is one line of it. The presets and the review rule packs
now carry specific security rules per stack, but no reviewer thinks about a change the way an information-security
engineer does: what is being protected, who can reach it, how it could be abused. And nothing looks at the risks
that come with building through SpecClaw itself: change records are committed to git and quote command output,
agents read issue and PR text, tokens sit in `.specclaw/.env`, and scripts build shell commands from change names.

## Proposed Solution

Add an `infosec-reviewer` subagent, `plugins/specclaw/agents/infosec-reviewer.md`, that reviews a change like an
InfoSec engineer who knows how SpecClaw works.

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

## Scope

### In Scope
- `agents/infosec-reviewer.md`, the verify step that spawns it, and the `workflow.security_review` config key.
- A small test that the agent file and the config key are well formed, registered in CI.
- One patch version bump.

### Out of Scope
- Gating the PR or the loop on its verdict (a follow-up once it has been measured).
- Running scanners or pen-test style probes (separate changes).
- Threat-modelling at propose or plan time (a follow-up).
- Any change to `code-reviewer`.

## Impact

- **Size:** bounded (adds one agent file, one verify step, one config key, one test)
- **Files affected:** 5 (estimated) plus the version files
- **Complexity:** small
- **Risk:** low (off by default)

## Open Questions

- Should a `BLOCK` eventually block the PR, as `workflow.code_review_block` does? Left for a follow-up.
- Which model? Proposed `models.review`, the same as `code-reviewer`.
