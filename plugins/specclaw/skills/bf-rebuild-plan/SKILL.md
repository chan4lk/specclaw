---
description: Read the five .specclaw/analysis/*.md documents (codebase-report, architecture, domain-model, functional-spec, module-map) — plus, when present, decisions.md, clarifications.md, and .specclaw/baseline/manifest.json/scenarios.md — and write or refresh an ordered .specclaw/analysis/rebuild-backlog.md: the application decomposed into individually-proposable features, grouped under the MOD-### migration modules from module-map.md in the map's own dependency order (foundations first) and sequenced by dependency and readiness within each, each item declaring its module and carrying its acceptance basis, a computed Gate (blocked/open-questions/clear against unanswered clarify questions) and Verification state (verifiable/pending-capture/unverifiable/no-baseline-data against baseline fixtures), and a "what a human still needs to supply" callout. When /specclaw:bf-quality has measured the tree, each module with an open hotspot at or above the configured severity floor also gets one bash-written QUALITY-REMEDIATION item, gated behind its own module's functional items and accepted by measurement (quality-delta.json) rather than by fixture replay; absent that measurement nothing about the document changes. Adds a bash-computed per-module coverage rollup and a recommended next module to build, stated with its reasons. `--module MOD-###` (re)plans one module, leaving every other module's items untouched in the merged output. First-ever run generates from scratch; every subsequent run requires `--refresh`, which recomputes Gate/Verification for every item, applies new decisions, and never renumbers, deletes, or disturbs a human-added status note. Read-only: no TTY or credential prompts, no lifecycle gate, creates nothing in changes/, calls no lifecycle command. Use after running /specclaw:bf-analyze, /specclaw:bf-architecture, and /specclaw:bf-domain — and, ideally, /specclaw:bf-clarify and /specclaw:bf-baseline — when you want an ordered, decision-aware list of what to /specclaw:propose to rebuild an existing (possibly legacy) app in a new stack.
---

# specclaw bf-rebuild-plan

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Turn the four analysis documents — plus, when present, `decisions.md`, `clarifications.md`, and the baseline outputs (`manifest.json`/`scenarios.md`) — into a living, ID-stable rebuild backlog. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`architecture`/`domain`/`clarify`/`baseline` pattern.

Determine the invocation mode from the user's message: **refresh mode** if it contains `--refresh`, **default mode** otherwise. Additionally, if the message contains `--module MOD-###`, this is a **module-scoped run**: pass that flag through to both `collect` and `render`, unchanged.

## Step 1 — Collect

```bash
mkdir -p .specclaw/analysis/.collect
specclaw-bf-rebuild-collect collect .specclaw [--refresh] [--module MOD-###] > .specclaw/analysis/.collect/rebuild-plan.json
```

Pass `--refresh` only in refresh mode, and `--module MOD-###` only if the user named a module. **Check the exit status before spawning anything below**, and never hand the agent a path to a half-written file. This single step:

- Checks that all five `.specclaw/analysis/*.md` documents exist — the four analysis documents plus `module-map.md`, which declares the `MOD-###` modules every backlog item is grouped under. **If it exits non-zero for this reason, surface its stderr message to the user verbatim and stop** — it names exactly which document(s) are missing and which command produces each (`module-map.md` comes from `/specclaw:bf-domain`). Don't retry, don't attempt a partial backlog from partial input, and never invent a grouping to work around a missing map.
- **Fails if `--module` names no active module in the map**, listing the ones that do exist. A withdrawn module cannot be planned — its id stays claimed as a tombstone.
- **If `.specclaw/analysis/rebuild-backlog.md` already exists and `--refresh` was not passed, it exits non-zero with a refusal message** — surface that message verbatim and stop. Do not delete or archive the file yourself; tell the user to re-run with `--refresh`, or to archive/delete it manually first if they genuinely want a from-scratch run.
- Otherwise emits one JSON object to stdout: the module roster from `module-map.md` (each module's id, name, active/withdrawn status, `DR-###` rules, and dependencies) together with the map's own `PROPOSED`/`CONFIRMED` status and this run's `module_scope`; the five documents' paths/line counts; which optional inputs are present (`decisions.md`, `clarifications.md`, `.specclaw/baseline/manifest.json`, `.specclaw/baseline/scenarios.md`) with their resolved paths; every `clarifications.md` question's `id`/`type`/`blocking`/`answered`/`rules`/`items` (ID-level facts only, no prose); which `CQ-###` ids have a recorded decision; the `scenarios.md` roster and `manifest.json` fixtures (`id`/`rules`/`item`); whether a "No Legacy Behaviour Exists" section is present; and — in refresh mode — every existing `BL-###` item's `id`/`title`/`depends_on`/`rules`/`status`/prior Gate/Verification. It also reports the next free `BL-###` id.

## Step 2 — Spawn the planning agent

`Agent` tool, `subagent_type: "bf-rebuild-planner"`, on the model from `config.yaml` `models.review` (default: `anthropic/claude-sonnet-4-5`) — same model family as its sibling analysis agents, since this is still read-only analysis of already-written documents, not spec/design authoring for a change. Pass as context:

- The path `.specclaw/analysis/.collect/rebuild-plan.json` — it reads that file directly.
- The resolved paths of the five analysis documents, plus whichever optional inputs are present (from `optional_inputs` in the JSON), for the agent to `Read` directly.
- **Tell the agent explicitly which mode it is running**: `first-run` (the JSON's `mode` field will read `"first-run"`) or `refresh` (`"refresh"`).
- **Tell it explicitly whether this run is module-scoped**, and to which `MOD-###` (the JSON's `module_scope`). In a scoped run the agent drafts only that module's items, directives, and coverage lines — see its own Behaviour 7.
- In refresh mode, also pass the resolved path of the *existing* `.specclaw/analysis/rebuild-backlog.md`, so the agent can read what's already there and avoid re-drafting anything it doesn't need to touch.

The agent writes **a draft file**, `.specclaw/analysis/.rebuild-plan-draft.md` — never the final `rebuild-backlog.md` itself. See `agents/bf-rebuild-planner.md` for exactly what belongs in it.

## Step 3 — Render

```bash
specclaw-bf-rebuild-collect render .specclaw .specclaw/analysis/.rebuild-plan-draft.md [--module MOD-###]
```

Pass the **same** `--module MOD-###` Step 1 was given, or the draft's Coverage Check will replace the whole section instead of only that module's lines — silently deleting the coverage record of every module the run never looked at.

Archives the prior `rebuild-backlog.md` (if any — same `.specclaw/analysis/archive/` directory `analyze`/`architecture`/`domain`/`clarify` already use), merges the draft with every preserved existing item, computes Gate and Verification for every active item from scratch (never trusting a stale value), computes **PROVISIONAL** status for every active item from scratch too — mechanically, by joining against any unanswered `CQ-NNN` whose `Source` field reads `Promoted from PQ-` (a pending-question-originated question — see `templates/pending-questions.md`), unioned with any `PROVISIONAL: BL-NNN | CQ-NNN | <reason>` directive the planner agent issued this run for a match its own semantic reading caught (Behaviour 5) that the mechanical join couldn't reach — computes dependency-rank-then-readiness ordering, renders struck items as one-line tombstones and deferred items into their own section, computes the refresh change report by diffing against the prior file's own stored Gate/Verification lines, and writes `.specclaw/analysis/rebuild-backlog.md`. Deletes the draft file on success. **If it exits non-zero, surface its stderr message to the user verbatim and stop.**

`render` also computes each item's **UI fidelity** line, when — and only when — that item renders a screen. Three inputs, all mechanical: the `SQ-013` UI fidelity policy read from `decisions.md`'s literal structure (a `### SQ-013 —` heading plus one of the literal tokens `FAITHFUL`/`THEME-ONLY`/`REINTERPRET` in its `Decision:` line — the same discipline `sanction-check` uses, never inferred and never defaulted to the least-work option); whether the item renders a screen (its own `SCR-###` citations, unioned with this run's `SCREEN-BEARING:` directive from the planner agent, since bash cannot know this on its own when `/specclaw:bf-ui` has never run); and whether the `.specclaw/ui/` artifacts the policy needs actually exist.

- **Decided `FAITHFUL`/`THEME-ONLY`, artifacts present:** each screen-bearing item's line names the `SCR-###` entries and `TK-` token groups it is held to (`FAITHFUL` additionally holds it to those screens' layout structure). The Coverage Check gains a bash-computed `### UI Screen Coverage (SCR)` subsection: every `SCR-###` in `ui-inventory.md` is either cited by at least one active item, or explicitly excluded with a stated reason via an `SCR-OUT-OF-SCOPE:` directive — anything else is reported as an unmapped gap, at screen granularity, the same way capability coverage is reported at bullet granularity.
- **Decided `FAITHFUL`/`THEME-ONLY`, artifacts missing:** one loud warning in the status header **naming every missing artifact** (plus the same warning on stderr), and every screen-bearing item sits at `OPEN QUESTIONS` with its UI fidelity line reading `⚠ UI GROUNDING MISSING`. Never a silent degradation — a backlog cannot state a UI acceptance basis it has no grounding for, and it does not pretend to.
- **Undecided `SQ-013` with screen-bearing items:** those items sit at `OPEN QUESTIONS` naming `SQ-013` directly.
- **Decided `REINTERPRET`:** no UI line on any item, no coverage subsection, no warning — one line in the status header recording that the policy makes the legacy UI reference material only. A project that answers `REINTERPRET` does no extra work anywhere.

This never makes UI a golden-master seam. A cited `SCR-###` is an acceptance reference, not a proof: visual fidelity is established by a named human signing `/specclaw:bf-ui --checklist`'s `ui-review.md` against recorded screenshots, never by `/specclaw:bf-replay`.

PROVISIONAL is soft-block and independent of Gate/Verification — an item can be `CLEAR`/`VERIFIABLE` and still carry the `⚠ PROVISIONAL — pending CQ-NNN` marker right after its heading. Unlike Gate/Verification (which react to any answered/unanswered CQ), PROVISIONAL is recomputed fresh from nothing every run: it never persists from a prior refresh's own rendered marker, so a question answered under `decisions.md`'s `## Decisions` clears it automatically the moment its `CQ-NNN` stops being unanswered — no manual cleanup, and no directive needed to *remove* a marker, only to add one.

`render` also computes the **Stub Retirement** section and each consuming item's `⚠ STUB-BACKED` marker, from `.specclaw/analysis/module-stubs.md` (the dependency-bypass registry, `templates/CONTRACT.md` (m)). Both are recomputed from nothing every run, the same tier as `PROVISIONAL` — retiring a stub clears every marker automatically, and no directive is ever needed to remove one. A project with no registry gets neither, silently.

The marker is deliberately **not** folded into the `Verification:` line. `Verification:` answers "is there a fixture for this?"; taint answers "was the thing under test real?" — orthogonal, and collapsing them would let a `VERIFIABLE` item read as fully proven when part of what it was checked against was a placeholder.

**Retirement is a human/Claude handoff, and the rendered block names the actor for every step.** The trigger is narrow and declared: a stub is only listed as *ready to retire* when the item it substitutes carries a line beginning `BUILT:` in its own `**Status notes (human-added):**` block. Prose is never parsed — specclaw records no built state, and reading "done last week" as completion would be exactly the guess this mechanism prevents. Who does what:

| Step | Actor |
|---|---|
| Write the `BUILT:` note once the real item is merged | **human** |
| List retirable stubs + the exact replay commands | **Claude** (this command, bash-computed) |
| Remove or disable the stub code | **human** decides; Claude may make the edit when asked |
| Flip `ACTIVE` → `RETIRING` | **human**, or Claude at their explicit word |
| Re-run the printed replays for every consumer | **Claude** |
| Flip → `RETIRED` citing the clean run id | **Claude**, and *only* on a clean run |
| Decide what a FAIL means (stub back in, or fix the real module) | **human** |

**Never retire a stub on an unclean run, and never remove stub code on your own initiative.** The three-state flow exists because with only `ACTIVE`/`RETIRED` the run that proves a stub is gone is itself stamped tainted, and flipping early leaves a failing re-replay falsely marked retired.

A **legacy `item-split` `ST-###` entry** — recorded before item splits had their own registry — is listed separately under *Legacy item-split entries (nothing to retire)*, excluded from taint and from the retirement flow. It fakes nothing, so there is no stub code to remove and no re-replay to run. `ST-###` ids are permanent and entries are never rewritten, so nothing migrates it; the block names the manual step (`split-append`) if resume tracking is wanted.

`render` also computes the **Item Splits** section and each affected item's `⚠ PARTIALLY BUILT` marker from `.specclaw/analysis/item-splits.md` (`templates/CONTRACT.md` (o)) — recomputed from nothing every run, the same tier as `PROVISIONAL` and `STUB-BACKED`, so a split reaching `COMPLETE` clears the marker by regeneration alone. A project with no registry gets one line saying so.

**This is the one place a rendering command writes into a registry, and the write is deliberately narrow.** When every id in an entry's `Blocked until` list carries a declared `BUILT:` line in its own **Status notes** block, `render` flips that entry `ACTIVE → READY-TO-RESUME` — the `Status` line only, one direction only, never back, no other field touched, and it prints a `WARN` naming the entry so the transition is never silent. The same narrow declared trigger stub retirement uses; prose is never parsed.

Why bash owns this one when it only *offers* stub retirement: the transition is a **pure function of declared data** (the blocked-until ids × their `BUILT:` notes), so there is no human judgement to defer to. Leaving it to a manual flip would make a stale `ACTIVE` indistinguishable from "nobody got round to it", and `/specclaw:propose`'s resume flow cannot tell those apart. `COMPLETE` is a handoff instead — it needs a clean `/specclaw:bf-replay --item BL-###` run to cite, and `split-update` refuses it straight from `ACTIVE`.

| Step | Actor |
|---|---|
| Write the `BUILT:` note on each blocked-until item once it is merged | **human** |
| Flip `ACTIVE` → `READY-TO-RESUME` | **bash**, here, automatically |
| Propose the remaining scope (`/specclaw:propose BL-###` resumes it) | **Claude** |
| Flip → `COMPLETE` citing a clean `--item` run id | **Claude**, and *only* on a clean run |
| Decide what a FAIL means | **human** |

## Step 4 — Regenerate the module status view

```bash
specclaw-bf-rebuild-collect module-status .specclaw
```

Deterministic, read-only, cheap. Writes `.specclaw/analysis/module-status.md`: one row per module — backlog items planned/total, baseline scenarios captured/designed, the latest module-scoped replay verdict with its date, the count of **stub-tainted items**, and the count of open questions naming that module. Run it here because this is the moment its inputs are freshest; an operator can also run it any time on its own.

The stub-tainted column counts this module's items whose **latest** retained replay run rested on an `ACTIVE` bypass stub, and the verdict cell reads `PASS*` rather than `PASS` while that count is non-zero. Unlike the verdict column — which only sees module-scoped runs — this one counts runs at every scope, because which items a run exercised and which of those rested on a stub is a per-item fact no scope distorts. A `## Stubs In Effect By Module` section lists, per module, the `ST-###` entries faking **that** module for other people's items, so "who is waiting on the real MOD-005" is one lookup.

It is a **status view, not evidence**: regenerated in full every invocation and deliberately exempt from archive-then-replace, because every number in it is recomputed from documents whose own history is already archived. Nothing reads it and nothing computes from it.

**If it exits non-zero, surface the message and continue** — the only failure is a missing `module-map.md`, which Step 1 would already have caught, and a missing status view never invalidates the backlog this run just wrote.

## Step 5 — Present a summary

- **First run:** backlog item count, a one-line note on the sequencing rationale, any Coverage Check exclusions, and the status header's counts (Gate/Verification/Provisional) and recommended next item.
- **Either mode — the module picture, always:** the module count and per-module item counts from `render`'s own summary line; the **recommended next module to build** together with the reasons the status header states for it, never a bare name; and the per-module lines from the Coverage Check's `### Module Coverage Rollup`. If the rollup reads "not computable", say so plainly rather than omitting it — it means the coverage lines are not in the countable form and the numbers genuinely aren't known.
  - **Surface `render`'s module warnings verbatim.** There are four, and each one means the backlog is describing something a human needs to fix: `module-map.md` is not `CONFIRMED`; a module dependency **cycle** (in which case there is no recommended next module, and the reason is the cycle rather than any module being unready); items left **unassigned** because they declare no `**Module:**` field; and items declaring a `MOD-###` the map does not define. Name the affected items and modules directly — burying these in the file defeats the point of computing them.
  - If the map is unconfirmed, repeat the one-sentence reason: this backlog's grouping and sequencing rest on a proposal no human has signed off, and confirming it is an edit to `module-map.md`'s own `**Status:**` line.
- **Module-scoped run (`--module`):** say explicitly which module was re-planned and that every other module's items, coverage lines, and human-added status notes were preserved untouched. If the agent reported a new item belonging to a *different* module, relay that — it was deliberately not drafted this run, and it needs its own scoped run.
- **Either mode, if the UI fidelity workstream is active:** relay the status header's UI fidelity block. If `render` emitted the missing-artifacts warning, **surface it verbatim and name the affected items** — that warning is the whole reason the check exists, and burying it in the file defeats it. Name any unmapped `SCR-###` from the UI Screen Coverage subsection too. Under `REINTERPRET`, say nothing about UI *fidelity* — no item is held to the legacy appearance. Screens are still mapped, so an unmapped `SCR-###` in the UI Screen Coverage subsection is still worth naming: under that policy it means a screen whose redesign nobody will be asked to approve.
- **Either mode, if any bypass stub is active:** relay the **Stub Retirement** section's *Ready to retire* entries directly, with the replay commands — that is a work list someone can act on today, and burying it in the file wastes it. Name any `⚠ STUB-BACKED` items and say plainly that their replay verdicts carry the marker until the stub is retired. Say nothing about stubs when there is no registry.
- **Either mode, if any item split is open:** relay the **Item Splits** section. Name every `⚠ PARTIALLY BUILT` item and what it is still missing — an item that looks planned, gated and verifiable but is missing a layer somebody deferred is exactly the thing a reader will otherwise mistake for finished. **Surface every `READY-TO-RESUME` flip this run made verbatim** (`render` prints a `WARN` per entry): that is the moment deferred work became actionable, and it is the single most useful line in the run for whoever is deciding what to do next. Say plainly that `/specclaw:propose BL-###` on such an item resumes it — proposing only the remainder, citing the earlier slice's own evidence — rather than starting it over. Say nothing about splits when there is no registry.
- **Refresh:** the rendered Change Report section verbatim — items newly unblocked, newly verifiable, struck/deferred/revised/added, and the recommended next item. Name any currently-`PROVISIONAL` item directly (from the status header's count and the Coverage Check's "Open Questions Blocking Readiness" subsection) — don't make the user go find it in the rendered file themselves.

**Remind the user to `git add .specclaw/analysis/*.md`** (including the refreshed `rebuild-backlog.md`) if these files aren't already tracked — grounding the lifecycle in them via `context.pin` only works once `git ls-files` can see them, since `specclaw-discover-context` enumerates candidates that way. See `docs/rebuild-workflow.md` for the full pin/grounding recipe.

## Step 6 — Show what comes next

```bash
specclaw-bf-status .specclaw --next
```

Render its output **verbatim**, after everything above — never instead of it. Read-only, writes nothing, costs a second.

This answers a different question from the summary above and does not replace it. Step 5's *recommended next item* and *recommended next module* are **within** this backlog: which `BL-###` to build, computed by `render` from dependency rank and readiness. This is the per-**phase** view: which `bf-*` command the rebuild as a whole is waiting on. Report both; they are not alternatives.

**Only if this run completed.** Steps 1 and 3 both say to surface stderr and stop — that means stop. A run that did not finish must never print a next step, which would read as though the phase advanced when it did not. Step 4's `module-status` failure is the one exception the skill already carves out: it is non-fatal, the backlog was still written, so guidance still applies.

**Never work the next step out yourself.** `specclaw-bf-status` owns the lifecycle ordering for every `bf-*` command — which phase follows which, which open items are human work, and which command clears them. A next phase decided here would be a second copy of that ordering, diverging the moment either side changes.

## What this command does not do

`/specclaw:bf-rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls **no** lifecycle skill or script — it only reads its input documents and writes one file. The operator still runs `/specclaw:propose "<item>"` themselves for each backlog entry, exactly as they would for any other feature idea. This command does not, and should not, ever be extended to auto-invoke `/specclaw:propose` — that would silently reintroduce the lifecycle coupling this command is deliberately designed to avoid.

The backlog is an acceptance basis plus a computed Gate/Verification state — it does not, and cannot, replace golden-master outputs or human-supplied external-format/DLL/COM semantics for verifying a truly faithful rebuild. A `VERIFIABLE` item has a matching captured fixture; it does not mean the fixture's assertions were exhaustive. See each item's "Verification inputs needed" field, its computed `**Verification:**` line, and `docs/rebuild-workflow.md`'s Fidelity limitation section.

A `QUALITY-MEASURED` item carries the same caveat from the other direction. Its `**Quality state:** DONE` means the rebuilt module measured within the configured thresholds and regressed on no dimension — it does not mean the module is well designed, and it says nothing about behaviour. The claim is made at module × metric grain, which is the finest grain `quality-delta.json` can carry: a `QI-###` names a legacy file and function, and neither exists in the target to be measured again. Thresholds themselves are a project's own choice in `config.yaml`.

`/specclaw:bf-rebuild-plan` never regenerates an existing backlog from scratch on a bare re-run, never renumbers a `BL-###` id, never deletes a struck or deferred item, and never touches a `**Status notes (human-added):**` block a human wrote into an item — those are the one hard invariant this command protects across every `--refresh`.

It never writes to `module-stubs.md`. Creating an entry is `/specclaw:propose`'s job (from a human's explicit choice), completing one is `/specclaw:build`'s, and retiring one is a human decision Claude executes step by step. This command only *reads* the registry — it lists what could be retired and marks what is stub-backed, and it never flips a status, never edits stub code, and never concludes a stub is retirable from anything but a declared `BUILT:` note.

It writes to `item-splits.md` in **exactly one** way: the `ACTIVE → READY-TO-RESUME` `Status` line, when every blocked-until item carries a declared `BUILT:` note. It never writes any other field, never walks a status back, never creates an entry (that is `/specclaw:propose`'s job, from a human's choice), and never marks one `COMPLETE` — that needs a clean `/specclaw:bf-replay --item` run to cite, and belongs to whoever ran it.

It never **derives** an item's module from that item's rules. A module is declared by the planner agent in the item's own `**Module:**` field and read mechanically from there; an item with no usable declaration is rendered under `## Unassigned` with a warning, never quietly filed into whichever module happens to own its rules. It never collapses a module into a single backlog item — a module groups items that already exist at capability-bullet granularity, and item granularity rules are untouched by this hierarchy. It never orders modules by anything but the map's own `Depends on` fields, and when those describe a cycle it says so and recommends no module rather than printing a rank the iteration cap happened to stop at. It never writes into `module-map.md`: confirming, renaming, or regrouping a module is `/specclaw:bf-domain`'s job and a human's decision, and a `--module` run against an unconfirmed map still runs — it just says, on the backlog's own face, that the grouping is unconfirmed.
