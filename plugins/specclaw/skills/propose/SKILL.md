---
description: Draft a new change proposal. INVOKE IMMEDIATELY whenever the user mentions a proposal, feature idea, change request, new initiative, or anything they want to add/build/implement — do NOT gather details conversationally first. The skill itself will ask for any missing information after invocation. Creates .specclaw/changes/<name>/proposal.md with problem statement, solution, scope, impact, and open questions. When party.enabled is set, also runs the adversarial review panel over the draft — asking first, unless party.default — and writes party-report.md. The first step in the propose → plan → build → verify → pr lifecycle.
---

# specclaw propose

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

**Timing (change 028).** Open a phase span when you start and close it when the artifact is written — `specclaw-timer start .specclaw <change> propose --kind phase --label propose || true`, then `specclaw-timer stop .specclaw <change> propose || true`. Cheap, and it finally answers how long this phase costs us. Both calls end in `|| true`: a stopwatch is never a reason to stop.

Create a new proposal for a change.

**If the user hasn't yet provided enough detail to draft the proposal (e.g. they just said "i have a proposal" with no specifics), ask once for the essentials inside this skill — what's the idea, what problem does it solve — then proceed to the steps below. Do not wait for a separate turn to invoke this skill.**

1. **Target-foundation gate** (brownfield rebuilds only — inert everywhere else). **Run this before creating or renaming anything:**

```bash
specclaw-bf-bootstrap foundation-check .specclaw
```

**If `applicable` is `false`, continue to step 1b** — there is no rebuild backlog, so this project is not a brownfield rebuild target and nothing here applies. Say nothing about it.

**If the command does not run at all** — `command not found`, any non-zero exit, or no JSON on stdout — you cannot read the gate, so fall back to the one signal that does not need it: **if `.specclaw/analysis/rebuild-backlog.md` does not exist, continue to step 1b silently.** No backlog means this is not a rebuild target, so the gate has nothing to protect and stopping an ordinary proposal because a brownfield-only binary is missing from an older install would be a pure false positive. If that file **does** exist, say the foundation gate could not be evaluated, name the command that failed, and stop — a brownfield project is exactly where this gate matters. The fail-closed rule at the bottom of this page governs a manifest this command *read* and distrusted; it does not govern a command that never ran.

**If `applicable` is `true` and `foundation_ready` is `false`, stop.** Do not offer or run the backfill, do not name the change, do not create the change directory, do not draft a proposal, do not run the dependency check. Relay the `reason`, then the `remedy` verbatim:

> Target rebuild foundation has not been created. Run `/specclaw:bf-bootstrap` first.

**Why this gate is absolute.** Without it, the first backlog item proposed inherits responsibility for inventing the application skeleton — and it inherits it *invisibly*, because nothing in the spec, the tasks or the verify report says "this item is also creating the app". That is how a screen-bearing item once shipped as a backend-only slice: the repo had no frontend, so the frontend was never anybody's task. A backlog item adds a capability to an application that already exists. If it does not exist yet, the answer is to create it deliberately, once, not to smuggle it into whichever item happened to be proposed first.

The one legitimate false positive is proposing an ordinary change **inside the legacy repo**, which also carries a `rebuild-backlog.md`. That is recorded once, explicitly, and attributably — never inferred, because there is no honest signal that distinguishes the two repos:

```bash
specclaw-bf-bootstrap not-applicable .specclaw \
  --reason "<why this repo is not the rebuild target>" \
  --declared-by "<name>, <YYYY-MM-DD>"
```

Both flags are required and the declaration is refused without them — same rule as a bypass's `Chosen by`. Ask the user for their name; do not supply one yourself.

When `foundation_ready` is `true`, continue silently. Mention the foundation only if the user asks.

1a. **Prototype-approval gate** (REINTERPRET rebuilds only — inert everywhere else). **Only run this if step 1 reported `applicable: true`.** If step 1 said `applicable: false`, this project is not a brownfield rebuild target, so skip straight to step 1b and say nothing — a greenfield project never runs this command at all.

```bash
specclaw-bf-prototype verify .specclaw
```

**If `applicable` is `false`, continue to step 1b silently** — this rebuild did not answer `SQ-013` as `REINTERPRET`, so there is no prototype stage and nothing here applies.

**If the command does not run at all** — `command not found`, any non-zero exit, or no JSON on stdout — apply the same rule as step 1: if `.specclaw/prototype/prototype-manifest.json` does not exist, continue to step 1b silently (an older install with no prototype stage, and no manifest for it to protect). If that file **does** exist, say the prototype gate could not be evaluated, name the command that failed, and stop.

**If `applicable` is `true` and `ready` is `false`, stop.** Do not name the change, do not create the change directory, do not draft a proposal. Relay the `reason`, then the `remedy` verbatim.

This check is deliberately whole-repo rather than per-item, and it runs for **every** change, not only screen-bearing ones. A repo that was bootstrapped while the prototype was approved, and whose approval was later withdrawn — or which had a `NOT-READY` manifest re-copied over a ready one — has an unapproved design underneath everything now being proposed. Gating only the screen-bearing items would let the rest of the work proceed on that foundation, which is the same mistake the foundation gate above exists to prevent, one level up.

The per-item half of this gate runs in step 2d, once the backlog item is known.

1b. Name the change `<NNN>-<slug>` — e.g. `001-init-repo`:
   - **Backfill offer — do this first, because a backfill changes the next number.** Run `specclaw-renumber-changes .specclaw` with no `--apply`: it is dry-run by default and renames nothing. If it prints a plan, unnumbered folders exist — show the user the full `old → new` list and ask **once** whether to apply it. On a yes, re-run with `--apply`; on a no, proceed with creating the new numbered change alone. No "already asked" flag is needed: the offer is conditioned on unnumbered folders existing, so it self-clears the moment a backfill runs.
   - Run `specclaw-next-change-number .specclaw` for `<NNN>`, and slugify the user's idea (lowercase, hyphens, no spaces) for `<slug>`. Join them with a hyphen. Never format the number by hand — `specclaw-next-change-number` owns that rule and is the only place it lives.

   From here on `<change-name>` means the full numbered name, prefix included.
2. Create `.specclaw/changes/<change-name>/`.

2a. **Backlog check** (brownfield rebuilds only — inert everywhere else). **Run this once, here; steps 2b and 2c both read its output:**

```bash
specclaw-bf-rebuild-collect bypass-check .specclaw <BL-###|--title "<the item title>">
```

Pass the `BL-###` if the user named one; otherwise pass the title — always behind the `--title` flag, never as a bare positional, which is refused. **If the JSON says `"applicable": false`, skip straight to step 3** — there is no backlog, or this change isn't a backlog item, and neither 2b nor 2c applies. Relay the `reason` only when it reports an *ambiguous* title (the user has to name the id); the other reasons are just "this isn't a brownfield backlog item" and need no comment.

**If the command does not run at all** — `command not found`, any non-zero exit, or no JSON on stdout — apply the same fallback as the step 1 gate: **if `.specclaw/analysis/rebuild-backlog.md` does not exist, skip straight to step 3 silently.** If it does exist, say the dependency check could not be evaluated, name the command that failed, and stop rather than proposing a backlog item with its dependencies unread.

The check is read-only and idempotent — it writes nothing — so re-running it costs nothing if you lose its output.

2b. **Item-split resume check.** Step 2a's output carries a `splits` array — every non-`COMPLETE` `IS-###` split on this backlog item. **If it is empty (the normal case), skip to 2c.**

Otherwise this item has already been partly built, and this proposal is a **resume, not a fresh start**. Before anything else, present:

- **What was already implemented** — the entry's `implemented_now`, and the rules it covers (`rules_implemented`).
- **The evidence that implemented it** — `change`, `evidence` (PR/merge), `replay_evidence` (the run id). Cite these, don't paraphrase them; they are what makes "already built" checkable rather than asserted.
- **What remains deferred** — `deferred`, plus `rules_deferred` and `layers_deferred`.
- **Which blockers are now satisfied** — `blocked_until_built` vs `blocked_until_unbuilt`.

Then, by the split's `status`:

| `status` | What to do |
|---|---|
| `READY-TO-RESUME` | Every blocker is built. **Propose only the deferred scope**, citing the `IS-###`. |
| `ACTIVE` with `resume_ready: true` | Every blocker now carries a `BUILT:` note but no `--refresh` has run since. Say so, and offer to run `/specclaw:bf-rebuild-plan --refresh` (which flips the state mechanically) before resuming. |
| `ACTIVE` with `resume_ready: false` | Blockers named in `blocked_until_unbuilt` are still unbuilt. Say which, and that the deferred scope genuinely cannot resume yet. Offer: propose some *other* remaining scope if any exists, wait, or — if the user says those blockers **are** built — write the `BUILT:` note into their status notes so the question isn't asked again. |

**Never re-propose completed scope.** The proposal's scope section covers the remainder only, and `proposal.md` carries `## Resumes Split` citing the `IS-###`. Rebuilding the finished slice from scratch is the failure this record exists to prevent — the whole point of `IS-###` is that choosing item-split must never make implementation history disappear.

2c. **Dependency check.** Act on each dependency in step 2a's `dependencies` array, by its `action`:

| `action` | What it means | What to do |
|---|---|---|
| `ok-built` | The dependency carries a declared `BUILT:` note | Nothing. Mention it in passing. |
| `covered-by-active-stub` | An `ST-###` already fakes it *for this item* | Nothing new to choose. Name the `ST-###` in the proposal's bypass section. |
| `same-module-prerequisite` | Unmet, and in **this item's own module** | **Refuse.** Not bypassable — see below. |
| `stub-exists-not-consumed` | A stub fakes this dependency, but for other items | Offer to add this item to that entry (`stub-update --consumed-by-add`) rather than mint a second stub for the same thing. Still the human's call. |
| `needs-bypass` | Unmet, cross-module, no stub | **Elicit** — see below. |
| `dependency-struck` | The dependency was struck from the backlog | Not a dependency any more. Say so; the backlog's `Depends on:` is stale. |
| `dependency-unknown` | The id isn't in the backlog at all | Report it as a backlog integrity problem. Do **not** treat it as either met or unmet. |
| `deferred-by-split` | A non-`COMPLETE` `IS-###` already defers the scope needing it | **Nothing to choose.** Name the `IS-###`. **Do not offer the strategies again** — the human already decided this, and accepting a second answer would produce two records of one deferral. |

**If any `same-module-prerequisite` exists, stop.** Name the prerequisite and say plainly that a same-module dependency is the item's own groundwork, not a cross-boundary wait — stubbing it would mean stubbing part of the very thing being built. The options are to build the prerequisite first, or to propose a smaller slice of this item that doesn't need it. Do not offer the four strategies for it, and do not create a registry entry.

**If any `needs-bypass` exists, stop and ask.** Present *each* unmet dependency separately with these six options, and **ground every strategy sketch in what that dependency actually is** — read its backlog entry and its module's row in `module-map.md` first. Generic sketches ("stub the interface") are useless to someone deciding; a sketch for an auth module reads like *"dev-only auth stub issuing a fixed seeded user + role"*, for a ledger module like *"seeded ledger rows so posting has something to read"*.

1. **`stub-interface`** — <sketch grounded in this dependency>
2. **`mock-data`** — <sketch>
3. **`feature-flag`** — <sketch>
4. **`item-split`** — **propose a specific vertical slice**, not a layer cut. Name exactly what ships now and exactly what waits: *"the grid renders, calls a real endpoint, runs a real query against real persisted data — and only the auth integration waits for BL-001/BL-003."* Say when this looks like the best fit: nothing is faked, so nothing is tainted and nothing needs retiring.
   - **Prefer a thin end-to-end capability over a horizontal stack cut, and say so in the offer.** A vertical slice delivers something a user can open. A horizontal cut — every layer below the UI ships and the UI waits, or the reverse — produces an item that looks nearly finished and delivers nothing anyone can use, with its acceptance basis unmet and no fixture able to notice. The dependency that is actually missing is usually one seam, not one layer.
5. **The dependency is actually built** — specclaw records no built state, so it genuinely cannot tell. If the user says it is, offer to write `BUILT: <their evidence>` into that item's `**Status notes (human-added):**` block in `rebuild-backlog.md`, so the question isn't asked again.
6. **Abort and follow the recommended order** — build the dependency first. Always a legitimate answer, and often the right one.

**Never pick for the user, never default, and never proceed on silence.** A bypass is an explicit human choice (`templates/CONTRACT.md` (m.2)); this is the ask-don't-guess rule applied to dependencies. If the user answers only some of the dependencies, ask about the rest — don't infer the same strategy carries across.

For each chosen **stub** bypass (options 1–3), append the registry entry:

```bash
specclaw-bf-rebuild-collect stub-append .specclaw \
  --substitutes "BL-014 (MOD-005)" --strategy stub-interface \
  --consumed-by "<this item's BL-###>" --chosen-by "<user's name>, <YYYY-MM-DD>" \
  --summary "<the one-line sketch they chose>" [--mock-seed <path>]
```

It prints the new `ST-###`. `Fakes` and `Implementation` stay `not yet implemented` — those are the build step's to fill in with a real `file:line`, and writing them now would be inventing a citation. Ask the user for their name if you don't have it; the entry is refused without one.

### If the user chooses `item-split`

**A split is not a stub and does not go in `module-stubs.md`.** `stub-append --strategy item-split` is refused by name. Read `$CLAUDE_PLUGIN_ROOT/references/split-discipline.md`, then:

**First, state the split back and get it confirmed — itemised, not summarised.** Two lists, from the item's own acceptance basis (`bypass-check` reports it as `item.acceptance_basis_rules`):

- **Implemented now:** the scope, and the `DR-###` rules it covers.
- **Deferred:** the scope, and the `DR-###` rules it covers.

Every rule in the item's acceptance basis must appear in exactly one list. `split-append` refuses a partition with a rule in both halves, a rule in neither, or a rule the item doesn't cite — and the refusal is not a formality: a rule in neither half is scope nobody owns, so nothing can later tell whether it shipped.

**If the split removes an entire major layer, say so as a consequence and require explicit confirmation before recording it.** For a screen-bearing item losing its UI (`bypass-check` reports `item.screen_bearing`), the sentence to put in front of the user names what goes unmet:

> This split defers the entire UI layer. BL-010 renders SCR-004, so it would ship with nothing a user can see, and its UI acceptance basis (SCR-004, TK-001) would go unmet. Confirm explicitly if that is what you want.

`split-append` **refuses** that split without `--layer-removal-confirmed-by "<name>, <date>"`, so this is enforced, not merely advised. Do not supply that flag on your own initiative or reuse the chooser's name to satisfy it — it is a second, separate attestation, and the whole reason the field exists is that somebody was asked.

Then record it:

```bash
specclaw-bf-rebuild-collect split-append .specclaw \
  --item BL-010 --module MOD-002 \
  --reason "BL-001/BL-003 authentication and route guards are not built" \
  --unmet-deps "BL-001, BL-003" \
  --implemented-now "patient listing · search/filter · active-prescription query · paging · backend API · React Patient Grid" \
  --deferred "BL-001 authentication integration · BL-003 route-guard integration" \
  --rules-implemented "DR-014, DR-015" --rules-deferred "DR-002" \
  --layers-implemented "ui, api, domain, persistence" --layers-deferred "auth-integration" \
  --blocked-until "BL-001, BL-003" \
  --chosen-by "<user's name>, <YYYY-MM-DD>" --change "<change-name>" \
  --summary "<one line: which item was split, and what waits>"
```

It prints the new `IS-###`. `Evidence` and `Replay evidence` stay `not yet merged`/`not yet replayed` — the build and replay steps fill those in, and writing them now would be inventing a citation.

**What to tell the user after recording it**, in one breath: the item will render `⚠ PARTIALLY BUILT` in `rebuild-backlog.md`, an `/specclaw:bf-replay --item BL-###` run will report **PARTIAL** and cannot be the item's final acceptance, and the split returns automatically — `--refresh` flips it to `READY-TO-RESUME` as soon as every blocked-until item carries a declared `BUILT:` note. Nothing is tainted: a split fakes nothing.

2d. **Per-item prototype gate** (REINTERPRET rebuilds only — inert everywhere else). **Skip this entirely unless step 1a reported `applicable: true`.** Skip it too when step 2a said `applicable: false` — with no backlog item there is nothing to key on.

```bash
specclaw-bf-prototype verify .specclaw --item <the BL-### from step 2a>
```

**If `item_ready` is `false`, stop.** Relay `item_reason` verbatim — it names each screen and exactly what is wrong with it:

> Prototype screen(s) not approved for BL-0NN: SCR-004 → PS-003 (STALE), SCR-007 → (no prototype screen). Re-approve, re-record, re-copy.

An item that references no screen passes this check on step 1a's whole-repo result alone; nothing extra is required of it.

**Why per-item as well as whole-repo.** Step 1a proves the redesign as a whole was approved. This proves *this* item's screens were — which is a different claim, and the one that matters when the work about to be proposed is the work that builds those screens. A screen reading `STALE` means the prototype changed after the client signed it off, so the approval on file describes something that no longer exists; building from it would produce an interface nobody approved, with a signed approval sitting next to it saying otherwise.

3. Generate `proposal.md` from `$CLAUDE_PLUGIN_ROOT/templates/proposal.md`. Fill in: problem statement, proposed solution, scope (in / out), impact (files, complexity, risk), open questions.
   - **`## Dependency Bypass`:** one bullet per **stubbed** dependency, citing the `ST-###` from step 2c, the strategy, the chooser and date, and the concrete sketch. **Omit the whole section** when there was no stub bypass — which is the normal case.
   - **`## Item Split`:** present only when this proposal recorded an `IS-###` in step 2c. Cite the id, what ships now, what is deferred, the rules each half covers, what unblocks the remainder, and the chooser — plus the layer-removal confirmer when there was one. The scope section's **out** list must name the deferred scope explicitly; a split whose deferral appears nowhere in the scope section is a split the spec will quietly widen.
   - **`## Resumes Split`:** present only when step 2b found a non-`COMPLETE` split. Cite the `IS-###`, what the earlier slice built, its change/PR/replay evidence, and state that this proposal covers the remainder only.
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

   **b. Confirm before spending.** Compute the bill first — `seats × rounds`, where rounds is `specclaw-party get .specclaw rounds --default 2` — you need it either way.

   **Spawn budget (change 038).** Run `specclaw-party get .specclaw session_spawn_cap` (no `--default` — empty means unset, and this whole check is skipped: go straight to the `party.default` check below). When it prints a number, also run `specclaw-party spawn-budget check .specclaw` (today's cumulative spawns across every change) and add this panel's bill to it. If that sum would exceed the cap, the ask below fires **even if `party.default` is `true`** — quote the cap and the cumulative-plus-bill total alongside the usual roster line, so the operator sees exactly what pushed it over. If the sum stays under the cap, fall through to the normal check.

   If `specclaw-party get .specclaw default --default false` prints `true` **and** the spawn budget didn't force it above, skip the ask. Otherwise ask **once**, in a single message, quoting from `party/panel.json`:
   - the resolved `tier` and its `tier_source`;
   - the classifier's `rationale` **verbatim** — do not paraphrase or trim it; it is the field the operator uses to reject a bad read;
   - the seat list as `role (model)`;
   - the bill: `seats × rounds` spawns broken down per model. E.g. a five-seat `deep` panel at 2 rounds — "10 spawns: 4 × opus, 4 × sonnet, 2 × fable.";
   - **when the spawn budget forced this ask:** the cap and today's cumulative-plus-this-panel total, e.g. "session_spawn_cap is 20; today's spawns are already 16 — this panel would bring it to 26."

     Then stop and wait. Anything short of a clear yes means **do not run the panel**: say that `party/panel.json` (and `classification.json`) is all that was written — no findings, no report, no edit to `proposal.md` — and continue at step 5 with the proposal as it stands. **Record nothing to the spawn ledger in this case** — a panel that was asked about and declined never ran.

   **c. Round 1.** Spawn **every seat in `panel.json` in parallel** — all `Agent` calls in one message, `subagent_type` = the seat's `role`. Each seat's prompt contains **only** the path (or full text) of `.specclaw/changes/<change-name>/proposal.md` and the instruction that this is round 1. Nothing else: **no other seat's output, no `context.md`, no `patterns.md`, no spec, no code.** The blindness is deliberate and the charters promise it. Write each seat's **final message verbatim** to `.specclaw/changes/<change-name>/party/findings-r1/<role>.md` — create the directory first, one file per seat, named exactly for the `role` in `panel.json` (e.g. `party-security.md`). The filename is the authority on authorship: `specclaw-party` takes the role from it, not from the finding heading. A seat that returns nothing gets no file and is reported as `unheard` — never invent one.

   **d. Round 2.** Skip when `specclaw-party get .specclaw rounds --default 2` prints `1`. Otherwise re-spawn **the same seats, again in parallel in one message**, each with: `proposal.md`; **all** of `findings-r1/*.md`, every seat's including its own; and the instruction that this is round 2 — re-emit each of *your own* round-1 findings with `**Status:** upheld` or `**Status:** withdrawn — <reason>`, and you may rebut another seat's finding but only its author may withdraw it. Write each final message to `.specclaw/changes/<change-name>/party/findings-r2/<role>.md`.

   **e. Tally and report.**
   ```bash
   specclaw-party tally  .specclaw <change-name>
   specclaw-party report .specclaw <change-name>
   ```
   `tally` prints one verdict token — `APPROVED`, `APPROVED_WITH_NOTES`, or `CHANGES_REQUESTED` — computed in bash from the round-2 findings (round-1 when `rounds` is `1`). Read the token; never recompute or second-guess it. It **exits 1 on `CHANGES_REQUESTED` only when `block` is `true`** (`specclaw-party get .specclaw block --default false`); under the shipped `block: false` it exits 0 on every verdict, so exit 0 does not mean approved. `report` writes `changes/<change-name>/party-report.md`.

   **Exit 2 from `tally` prints no token and means round 2 did not run** — `findings-r2/` is missing or empty while `findings-r1/` holds findings. Do not treat that as approval and do not invent a verdict: an empty round 2 would otherwise tally as `APPROVED` over live objections on disk. Re-run step **d** for the seats that produced no round-2 file, then re-run `tally`. `report` still writes in this state, with a warning, so the round-1 findings are never lost.

   **Record the spend (change 038).** The panel actually ran, so record it regardless of whether `session_spawn_cap` is set — the ledger is the running total the cap is checked against, so a skipped record would undercount every check after it: `specclaw-party spawn-budget record .specclaw <change-name> <spawns>`, where `<spawns>` is the seat count alone if round 2 was skipped (`rounds: 1`), or seats × 2 otherwise.

   **f. Present and append.** Show `party-report.md` alongside the proposal in step 5, verdict first. Then make **one** edit to `proposal.md`: append the upheld findings under its existing `## Open Questions` heading, one line each, naming the seat — e.g. `- (party-security) Does a failed parse of the classifier answer fail open? — see party-report.md`. **Edit no other section.** The panel argues; it does not author: do not rewrite Problem, Proposed Solution, Scope or Impact in response to a finding. Approval stays the operator's — `CHANGES_REQUESTED` blocks nothing here. `party.block: true` makes it a hard stop for `/specclaw:plan`; it ships `false`.
4b. **Size the change** (spike / bounded / architectural) and write it into the proposal's
   `**Size:**` line under Impact.

   | Size | It is this when… | Artifacts `plan` writes |
   |---|---|---|
   | **spike** | the output is an *answer*, and anything built is throwaway | `findings.md` only — `build`, `verify` and `pr` are refused |
   | **bounded** | an existing flow in this repo is being altered — a flag, an endpoint, a one-file fix | `spec.md` (with an `## Approach` section carrying the file map) + `tasks.md`, **no `design.md`** |
   | **architectural** | a new subsystem, or an interface others will depend on | `spec.md` + `design.md` + `tasks.md` |

   **Announce the classification with its one-sentence reason** before presenting the proposal —
   *"this alters `specclaw-verify collect`, which already exists → bounded"* — so the operator can
   override it in the approval reply in one message rather than discovering the ceremony later.

   **When party mode ran, offer its tier as the default**: `thin → bounded`,
   `standard`/`deep` → `architectural`. The classifier has already judged depth; do not judge it
   twice. The mapping is a *default*, not a binding — two independent judgements, one seeding the
   other.

   **The approval gate does not scale with the size.** A five-line proposal for a bounded change
   still needs approval before `plan`. Ceremony scales; the gate never does.

5. Present the proposal to the user for review.
6. Update `.specclaw/STATUS.md` via `specclaw-update-status .specclaw`.
7. **GitHub sync** (if `github.sync: true` in `config.yaml`): run `specclaw-gh-sync create .specclaw <change-name>` to create a GitHub Issue for the proposal. Validation (proposal.md must exist) is enforced by `specclaw-validate-change`.
8. **Azure Boards sync** (if `azdo.boards.sync: true` in `config.yaml`): run `specclaw-azdo-issue create .specclaw <change-name>` to create a Work Item. Idempotent — safe to re-run.
9. **Once the user approves the proposal**, record the phase *and the size*: `specclaw-set-phase .specclaw <change-name> proposal approved --size <spike|bounded|architectural>`. If the operator overrode the classification in their approval reply, that is the size that gets recorded. A change recorded with no size reads as `architectural` everywhere — today's behaviour — so omitting the flag costs ceremony, never correctness. `specclaw-set-phase` is the only writer of phase state — it records `state.json` and upserts the Proposal row in `status.md`. Never hand-edit those rows. Until approval the template's `🟡 Draft` row stands.

Do not proceed to `/specclaw:plan` until the user has approved the proposal.

## What the dependency check never does

It never decides that a bypass is warranted, never picks a strategy, and never writes a registry entry the user didn't choose. `bypass-check` classifies; the human decides; bash records. An agent that picks a "sensible default" here has quietly converted a tracked, dated, attributable decision into an untracked one — which is the single failure mode this whole mechanism exists to prevent.

It also never infers that a dependency is built from prose. Only a declared `BUILT:` line in the item's own status notes counts. "Done last week", "shipped in #42", a ✅ — none of these are read, deliberately: a false positive here silently skips the elicitation that would have caught the unmet dependency.

**And a split never widens on its own.** The split the user selected is the split that happens. If drafting the proposal suggests the chosen partition is wrong — a rule sits awkwardly, a layer turns out to be needed — **stop and hand it back**. Moving one more rule into the deferred half without asking is precisely how a screen-bearing item once lost its entire frontend, and it is the reason `split-append` refuses a partition that does not account for the item's acceptance basis exactly.

## What the foundation gate never does

It never creates a foundation, never infers that one exists from the presence of source files, and never decides that a project doesn't need one. It reads a manifest that `/specclaw:bf-bootstrap` wrote, or it reads a `--not-applicable` declaration a named human made. Absent both, it stops and names the command — the same UX pattern as every other precondition gate in the pipeline.

It fails **closed**: a manifest that can't be parsed, carries an unknown schema, or claims readiness while recording a failed smoke check reports not-ready with the reason. Passing a gate on a file nobody could read would defeat the point of having it.

Nothing above applies to a project with no `rebuild-backlog.md`. Both `foundation-check` and `bypass-check` return `applicable: false` and propose behaves exactly as it always has — and if either command cannot run at all, the absence of that same file is the fallback signal, so a greenfield proposal is never blocked by a brownfield-only binary being missing. **A greenfield project is never gated here, on any path.**
