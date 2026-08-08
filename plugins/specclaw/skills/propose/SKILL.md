---
description: Draft a new change proposal. INVOKE IMMEDIATELY whenever the user mentions a proposal, feature idea, change request, new initiative, or anything they want to add/build/implement — do NOT gather details conversationally first. The skill itself will ask for any missing information after invocation. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. The first step in the propose → plan → build → verify → pr lifecycle.
---

# specclaw propose

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Create a new proposal for a change.

**If the user hasn't yet provided enough detail to draft the proposal (e.g. they just said "i have a proposal" with no specifics), ask once for the essentials inside this skill — what's the idea, what problem does it solve — then proceed to the steps below. Do not wait for a separate turn to invoke this skill.**

1. Name the change `<NNN>-<slug>` — e.g. `001-init-repo`:
   - **Backfill offer — do this first, because a backfill changes the next number.** Run `specclaw-renumber-changes .specclaw` with no `--apply`: it is dry-run by default and renames nothing. If it prints a plan, unnumbered folders exist — show the user the full `old → new` list and ask **once** whether to apply it. On a yes, re-run with `--apply`; on a no, proceed with creating the new numbered change alone. No "already asked" flag is needed: the offer is conditioned on unnumbered folders existing, so it self-clears the moment a backfill runs.
   - Run `specclaw-next-change-number .specclaw` for `<NNN>`, and slugify the user's idea (lowercase, hyphens, no spaces) for `<slug>`. Join them with a hyphen. Never format the number by hand — `specclaw-next-change-number` owns that rule and is the only place it lives.

   From here on `<change-name>` means the full numbered name, prefix included.
2. Create `.specclaw/changes/<change-name>/`.
3. Generate `proposal.md` from `$CLAUDE_PLUGIN_ROOT/templates/proposal.md`. Fill in: problem statement, proposed solution, scope (in / out), impact (files, complexity, risk), open questions.
   - Also generate `.specclaw/changes/<change-name>/status.md` from `$CLAUDE_PLUGIN_ROOT/templates/status.md`. Fill in: `{{title}}` and `{{change_name}}`, `{{date}}` / `{{updated}}` with today's date, and the phase rows — set Proposal status to `🟡 Draft` and the remaining phases (Spec, Design, Tasks, Build, Verify) to pending. Leave task/agent/issue sections empty for now.
4. Present the proposal to the user for review.
5. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
6. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.
7. **Azure Boards sync** (if `azdo.boards.sync: true` in `config.yaml`): run `specclaw-azdo-issue create .specclaw <change-name>` to create a Work Item. Idempotent — safe to re-run.
8. **Once the user approves the proposal**, record the phase: `specclaw-set-phase .specclaw <change-name> proposal approved`. `specclaw-set-phase` is the only writer of phase state — it records `state.json` and upserts the Proposal row in `status.md`. Never hand-edit those rows. Until approval the template's `🟡 Draft` row stands.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.
