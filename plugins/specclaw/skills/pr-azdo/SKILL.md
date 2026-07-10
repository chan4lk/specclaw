---
description: Create an Azure DevOps pull request for a verified change. Mirrors /specclaw:pr but targets ADO Repos via REST API instead of GitHub. Requires credentials from /specclaw:auth-azdo. Use when the project uses Azure DevOps instead of GitHub.
---

# specclaw pr-azdo

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create an Azure DevOps PR for a verified change.

1. **Validate:** `specclaw-validate-change .specclaw <change> pr`. Fails if `verify-report.md` is missing.
2. **Run:** `specclaw-azdo-pr .specclaw <change>` — **always** create the PR through this script, never hand-roll the ADO REST call. `specclaw-azdo-pr` stages and commits the full `.specclaw/changes/<change>/` planning trail (proposal, spec, design, tasks, status, verify-report) into the branch and **aborts if any of it is left uncommitted** — bypassing it ships a PR missing the proposal artifacts.
   - Requires `AZDO_TOKEN`, `AZDO_ORG`, `AZDO_PROJECT`, `AZDO_REPO` (set via `/specclaw:auth-azdo`).
   - **Test policy:** same gate as `/specclaw:pr` — prompts once, enforces on all runs.
   - **PR creation:** builds title (≤128 chars) from `proposal.md`, description from `spec.md` + `verify-report.md`, calls ADO REST API.
   - **Saves URL:** appends `**ADO PR:** <url>` to `status.md`.
3. **Update project context:** After the ADO PR URL is saved, rewrite `.specclaw/context.md` to incorporate decisions from this change:
   - Run `specclaw-update-context .specclaw <change>` — this outputs an LLM prompt.
   - Feed the prompt to a coding agent that rewrites `context.md` in place (architecture-doc style: replaces stale info, merges new decisions).
   - If `context.md` changed, commit it: `git add .specclaw/context.md && git commit -m "docs(context): update project context after <change>"` and push.
   - Errors here are non-blocking — warn and continue.
4. Report the ADO PR URL to the user.

**CI outer loop (if `loop.ci_gate: true`):** once the PR branch is pushed, the CI tier of `/specclaw:loop` (Step 3 / `specclaw-loop ci-poll`) polls Azure Pipelines runs and iterates fixes until they are green, or `loop.ci_max_iterations` / `loop.ci_timeout_seconds` halts and escalates. This is a cross-reference only — PR creation above is unchanged, and nothing extra runs when `loop.ci_gate` is false.
