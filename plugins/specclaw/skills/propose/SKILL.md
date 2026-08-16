---
description: Draft a new change proposal. INVOKE IMMEDIATELY whenever the user mentions a proposal, feature idea, change request, new initiative, or anything they want to add/build/implement — do NOT gather details conversationally first. The skill itself will ask for any missing information after invocation. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. When party.enabled is set, also runs the adversarial review panel over the draft — asking first, unless party.default — and writes party-report.md. The first step in the propose → plan → build → verify → pr lifecycle.
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
4. **Party panel (conditional).** Read the switch with the reader, never with your eyes:

   ```bash
   specclaw-party get .specclaw enabled --default false
   ```

   If that prints anything other than `true`, skip this step entirely — no `party/` directory, no prompt, no spawn, no mention of it in your reply. If `true`, work through **a–f** in order.

   **Every party config value on this page is read that way.** `specclaw-party get` is the only supported reader of the `party:` block: it seeks to the column-0 `party:` line and resolves the key inside that window. Do not `Read` `config.yaml` and look for the key, do not `grep` for it, do not use `yaml_val`. A whole-file read of `enabled:` finds `build.dynamic_agents.enabled` — `false` — seventy lines above the key you wanted, and the run that results is indistinguishable from party mode being correctly switched off.

   **a. Resolve the panel.** Run `specclaw-party panel .specclaw <change-name>` and branch on its exit code:
   - **0** — the roster is resolved and `changes/<change-name>/party/panel.json` is written. Go to **b**.
   - **2** — usage error, or `proposal.md` is missing/empty. Report the message, skip the rest of step 4, do not retry.
   - **10** — a classifier model turn is required. Bash cannot spawn subagents, so the script hands the turn to you:
     1. The **first line** of stdout is `target: <path>` — always `.specclaw/changes/<change-name>/party/classification.json`. **Everything after that line** is the classifier prompt.
     2. Invoke the `party-classifier` subagent via the `Agent` tool with `subagent_type: "party-classifier"`, passing that prompt verbatim.
     3. `party-classifier` has `tools: [Read]` and **cannot write files.** It returns its JSON object as its **final message, and you write that final message to the `target:` path.** This is the step a future author will skip; skipping it silently degrades the panel.
     4. Re-run `specclaw-party panel .specclaw <change-name>` — same command, same arguments. It now reads `classification.json` and exits 0.

     `panel` never asks twice — run the handshake at most once. If the re-run warns `no classification.json ... falling back to tier standard`, the classifier turn did not land: that is not fatal (exit 0, `tier_source: fallback`), but say so when you present the roster — the tier was defaulted, not judged.

   **b. Confirm before spending.** If `specclaw-party get .specclaw default --default false` prints `true`, skip the ask. Otherwise ask **once**, in a single message, quoting from `party/panel.json`:
   - the resolved `tier` and its `tier_source`;
   - the classifier's `rationale` **verbatim** — do not paraphrase or trim it; it is the field the operator uses to reject a bad read;
   - the seat list as `role (model)`;
   - the bill: `seats × rounds` spawns broken down per model, where rounds is `specclaw-party get .specclaw rounds --default 2`. E.g. a five-seat `deep` panel at 2 rounds — "10 spawns: 4 × opus, 4 × sonnet, 2 × fable."

     Then stop and wait. Anything short of a clear yes means **do not run the panel**: say that `party/panel.json` (and `classification.json`) is all that was written — no findings, no report, no edit to `proposal.md` — and continue at step 5 with the proposal as it stands.

   **c. Round 1.** Spawn **every seat in `panel.json` in parallel** — all `Agent` calls in one message, `subagent_type` = the seat's `role`. Each seat's prompt contains **only** the path (or full text) of `.specclaw/changes/<change-name>/proposal.md` and the instruction that this is round 1. Nothing else: **no other seat's output, no `context.md`, no `patterns.md`, no spec, no code.** The blindness is deliberate and the charters promise it. Write each seat's **final message verbatim** to `.specclaw/changes/<change-name>/party/findings-r1/<role>.md` — create the directory first, one file per seat, named exactly for the `role` in `panel.json` (e.g. `party-security.md`). The filename is the authority on authorship: `specclaw-party` takes the role from it, not from the finding heading. A seat that returns nothing gets no file and is reported as `unheard` — never invent one.

   **d. Round 2.** Skip when `specclaw-party get .specclaw rounds --default 2` prints `1`. Otherwise re-spawn **the same seats, again in parallel in one message**, each with: `proposal.md`; **all** of `findings-r1/*.md`, every seat's including its own; and the instruction that this is round 2 — re-emit each of *your own* round-1 findings with `**Status:** upheld` or `**Status:** withdrawn — <reason>`, and you may rebut another seat's finding but only its author may withdraw it. Write each final message to `.specclaw/changes/<change-name>/party/findings-r2/<role>.md`.

   **e. Tally and report.**
   ```bash
   specclaw-party tally  .specclaw <change-name>
   specclaw-party report .specclaw <change-name>
   ```
   `tally` prints one verdict token — `APPROVED`, `APPROVED_WITH_NOTES`, or `CHANGES_REQUESTED` — computed in bash from the round-2 findings (round-1 when `rounds` is `1`). Read the token; never recompute or second-guess it. It **exits 1 on `CHANGES_REQUESTED` only when `block` is `true`** (`specclaw-party get .specclaw block --default false`); under the shipped `block: false` it exits 0 on every verdict, so exit 0 does not mean approved. `report` writes `changes/<change-name>/party-report.md`.

   **Exit 2 from `tally` prints no token and means round 2 did not run** — `findings-r2/` is missing or empty while `findings-r1/` holds findings. Do not treat that as approval and do not invent a verdict: an empty round 2 would otherwise tally as `APPROVED` over live objections on disk. Re-run step **d** for the seats that produced no round-2 file, then re-run `tally`. `report` still writes in this state, with a warning, so the round-1 findings are never lost.

   **f. Present and append.** Show `party-report.md` alongside the proposal in step 5, verdict first. Then make **one** edit to `proposal.md`: append the upheld findings under its existing `## Open Questions` heading, one line each, naming the seat — e.g. `- (party-security) Does a failed parse of the classifier answer fail open? — see party-report.md`. **Edit no other section.** The panel argues; it does not author: do not rewrite Problem, Proposed Solution, Scope or Impact in response to a finding. Approval stays the operator's — `CHANGES_REQUESTED` blocks nothing here. `party.block: true` makes it a hard stop for `/specclaw:plan`; it ships `false`.
5. Present the proposal to the user for review.
6. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
7. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.
8. **Azure Boards sync** (if `azdo.boards.sync: true` in `config.yaml`): run `specclaw-azdo-issue create .specclaw <change-name>` to create a Work Item. Idempotent — safe to re-run.
9. **Once the user approves the proposal**, record the phase: `specclaw-set-phase .specclaw <change-name> proposal approved`. `specclaw-set-phase` is the only writer of phase state — it records `state.json` and upserts the Proposal row in `status.md`. Never hand-edit those rows. Until approval the template's `🟡 Draft` row stands.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.

## Teaching mode (if `teach.enabled: true`)

Check with `specclaw-teach .specclaw status`. When enabled, after presenting the proposal:

1. Show a **stack table** of every technology this change touches — libraries included, not just categories (`kafka` and `kafkajs` are different things to know) — with what each is for *in this project* and where it appears. Mark which parts are learning surface versus plumbing.
2. Ask for the user's level on **every row**: **(a)** never used it, **(b)** theory only, **(c)** shipped with it, **(d)** deep — via `AskUserQuestion`, batched 4 at a time in first-needed order. Record each: `specclaw-teach .specclaw level <tech> <a|b|c|d> self`. Being asked is not overhead — it's how the user sees the surface area of the work.
3. Spot-check every (c)/(d) claim with one specific question and correct it silently if it doesn't hold.

Never assume a level in either direction. Protocol: `references/teaching-mode.md`.
