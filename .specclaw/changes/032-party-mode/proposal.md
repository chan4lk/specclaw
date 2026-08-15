# Proposal: Party mode — an adversarial panel that argues a proposal before it becomes a plan

**Created:** 2026-08-15
**Status:** 🟡 Draft

## Problem

**A proposal is written by one model, in one pass, with one point of view — and nothing challenges it
before it becomes a spec, a design, a task list, and a branch.**

The lifecycle is `propose → plan → build → verify → pr`. Every quality gate specclaw owns sits at the
*end* of that chain: `code-reviewer` reviews code that is already written, `verify` checks an
implementation that already exists, the loop remediates a build that already ran. The one artifact
that determines what all of them will be spent on — `proposal.md` — gets no adversarial pass at all.
`skills/propose/SKILL.md:21` is the whole review step: *"Present the proposal to the user for
review."* The reviewer is the operator, reading prose on Discord, usually on a phone.

The cost of that asymmetry is visible in this repo's own proposals. `029-staged-files-auditor` shipped
six open questions, and at least three of them are the kind a dedicated role would have raised
*before* the proposal was presented rather than after:

- *"Is the auditor worth its token cost when Layer 1 already catches the reported failures?"* — a PO
  question about value per token, asked by the author about their own design.
- *"Does any existing automation depend on build opening the PR?"* — an Architect question about a
  blast radius the proposal itself introduces.
- *"Is specclaw fixing a symptom of missing ignore rules?"* — an inversion question that, if answered
  "yes", deletes a large part of the proposal.

Those questions survived into the artifact because the author had no counterparty. A proposal that
carries its own unanswered objections is a proposal that will spend planning tokens discovering them.

Three specific failure modes follow from single-perspective authoring:

1. **Solution-first framing.** The author commits to an approach in the Problem section and then
   writes a Scope that defends it. Nobody asks "what if we did nothing?" or "what is the one-line
   version of this?" — despite `code-reviewer` dimension 3 enforcing exactly that YAGNI standard on
   *code*. The standard exists; it is applied one phase too late.
2. **Security and operational concerns arrive at review.** `code-reviewer` dimension 2 is the first
   security pass in the lifecycle. By then the design is fixed and the finding is expensive: a
   security objection to a *proposal* costs a paragraph, the same objection to a *merged design*
   costs a rewrite.
3. **No recorded dissent.** When the operator approves a proposal, the reasoning that was *not*
   pursued vanishes. `.specclaw/learnings.md` and `patterns.md` capture lessons from builds; nothing
   captures the arguments that shaped a proposal, so the same debate reruns next quarter.

The same gap exists at the other end of the lifecycle. `/specclaw:loop` halts on four guardrails —
iteration cap, no-progress, regression, oscillation — and `specclaw-loop escalate` responds by
committing partial work and notifying the operator with the halt reason. A halt is precisely the
moment where the *strategy* is wrong, not the diff: the loop has proven by repetition that the
current approach cannot turn the gate green. Yet the escalation carries no analysis of *why the
approach is wrong* — the operator gets gate status and is left to diagnose it themselves.

## Proposed Solution

**Party mode: spawn a panel of role-specialised sub-agents that argue over an artifact, tally their
verdicts deterministically, and write a `party-report.md`.** Opt-in per invocation, switchable to
default-on by config.

### The panel

**Five real agents — one definition file each, each with its own model.** Not one parameterised
panelist wearing five hats: five entries under `agents/`, following the existing
`code-reviewer.md` / `spec-author.md` pattern (frontmatter `name` / `description` / `tools` /
`model`, then an identity + inputs + output-contract body). A panelist is a *subagent with a
standing charter*, discoverable in the agent list, reusable outside party mode, and independently
tunable — which a role string injected into a shared prompt is not.

| Agent | Lens | Its characteristic objection | Model |
|-------|------|------------------------------|-------|
| `party-ba` | Problem fidelity | "The stated problem is not the real problem. Evidence?" | `sonnet` |
| `party-po` | Value per token | "What is the cheapest thing that captures 80% of this? Why not do nothing?" | `sonnet` |
| `party-architect` | Structural fit | "This duplicates a concern that already lives elsewhere. Blast radius?" | `opus` |
| `party-security` | Failure and abuse | "What does this trust that it should not? What happens when it misfires?" | `opus` |
| `party-visionary` | Direction | "Does this compound, or is it a patch that makes the next change harder?" | **`fable`** |

**Model per role is the point, not a detail.** The roles are not doing the same work at different
prices — they are doing different work. Structural blast-radius reasoning and adversarial
"what-does-this-trust" reasoning need the strong tier (`opus`); requirements fidelity and
value-per-token arithmetic are well-served by `sonnet`; **the Visionary runs on `fable`** because its
job — does this compound, or does it make the next change harder — is the one genuinely open-ended,
long-horizon judgement on the panel, and it is the role most likely to produce the objection nobody
else can see. A weak model in that seat produces a horoscope.

Frontmatter carries the default; `party.models.<role>` in `config.yaml` overrides it per project, so
a cost-constrained repo can put the whole panel on `haiku` without editing the plugin.

**Different angles are enforced, not hoped for.** Each charter states what the role must attack, and
— critically — what it must *not* comment on. The Security Officer does not get to raise scope creep;
the PO does not get to raise injection risk. Overlapping charters are how five agents converge on the
same three findings, which is the failure mode this whole change lives or dies on (Open Question 1).

### The panel is sized to the proposal, not fixed

A one-paragraph "add a `--json` flag" proposal does not need a Visionary on `fable` asking whether it
compounds. A cross-cutting proposal that rewires four scripts and touches PR creation needs every seat
it can get. **A fixed five-seat panel is either overkill or under-powered on almost every proposal** —
and since the panel is the most expensive gate in the lifecycle, the wrong size is expensive in both
directions.

So the roster is **computed per proposal** by `specclaw-party panel`, following the precedent already
in this repo: `build.dynamic_agents` classifies each task into a tier and resolves a model from a
ladder. Same idea, one level up — classify the *artifact*, resolve a *roster*.

**Depth is judged by a `haiku` classifier, not counted by a script.** `agents/party-classifier.md`
(`model: haiku`, `tools: [Read]`) reads `proposal.md` and returns a tier plus the domain flags that
seat specialists:

```json
{"tier": "thin|standard|deep",
 "domains": ["security", "data", "ops"],
 "rationale": "one sentence",
 "signals": {"scope_breadth": "...", "blast_radius": "...", "unresolved": "..."}}
```

This is a deliberate exception to the repo's "the script owns every mechanical decision" rule, and
the reason is that **depth is not a mechanical decision**. Word count, bullet count and a keyword
list are proxies for a judgement, and each fails in an obvious way: a verbose trivial proposal scores
high, a terse dangerous one scores low, and the author model — which writes the proposal and benefits
from a smaller panel — can move every one of those numbers for free. A model that reads the prose is
judging the thing itself rather than its shadow. The cost is ~1 cheap spawn against a panel of 4–10
expensive ones, so classification is a rounding error on the bill it controls.

What the classifier weighs — stated in its charter, not left to taste: real blast radius (how many
subsystems change, not how many words describe them), how much of the design is still unresolved,
irreversibility, and whether the change touches trust boundaries, data shape, or release machinery.

**The script still owns everything after the tier.** `specclaw-party panel` takes the classifier's
JSON and resolves the roster deterministically — tier → seats, `always` force-seats, `min_seats` /
`max_seats` clamps, `panel.json` cache. Judgement is the model's; arithmetic stays in bash. That is
the same split as the tally, where a model writes the narrative and the script writes the verdict.

**Failure mode is fail-loud, not fail-quiet.** Unparseable JSON, an unknown tier, or a classifier
that errors → `panel` falls back to `standard` (never `thin`), records `"tier_source": "fallback"`
in `panel.json`, and says so on stdout. A cheap model silently downgrading a panel to two seats is
exactly the failure that would never be noticed.

**Tiers:**

| Tier | Roster | Spawns @ 2 rounds |
|------|--------|-------------------|
| **thin** | `party-po`, `party-architect` | 4 (2 sonnet, 2 opus) |
| **standard** | + `party-ba` | 6 |
| **deep** | + `party-visionary` (`fable`) | 8 |
| **any tier** | `party-security` seated on a `security` domain flag, or at `deep` | +2 |

Two seats is the floor — one agent is a review, not a panel — and `max_seats` is the ceiling.

**The proposal's own `Complexity:` / `Risk:` lines are a claim, not evidence.** They are written by
the same model that wrote the proposal, and a proposal that would rather not be argued with can just
claim `small` / `low`. The classifier's charter therefore says: treat those lines as **escalate-only**
— a `high` declaration raises the tier, a `low` one is ignored and the judgement stands on the
substance. Without that asymmetry the gate is opt-out by self-assessment, which is not a gate.

**The decision is written down.** `specclaw-party panel` caches to
`changes/<change>/party/panel.json` — the classifier's tier, its one-sentence rationale, the domain
flags, `tier_source` (`classifier` or `fallback`), and the resolved seats — the same way
`dynamic_agents` caches synthesized specs under `changes/<change>/agents/`. A panel you cannot audit
is a panel you cannot debug when it seats the wrong roles, and with a model in the loop the
rationale is the only thing that explains a surprising roster.

**Escape hatches, both directions.** `party.panel_mode: fixed` pins the roster to `party.panel`;
`party.always: [party-security]` force-seats a role at every tier; `/specclaw:propose --panel deep`
overrides the classifier for one run. Automatic sizing is the default, not a cage.

This also resolves the Fable cost objection honestly: **`fable` is seated only at `deep`**, so the
expensive seat appears on the proposals where an open-ended long-horizon read is worth paying for and
is absent from the rest. Note the contrast with `build.dynamic_agents`, which clamps Fable behind
`max_model` and `fable_max_fraction: 0.2` — build spawns one agent *per task*, so its Fable share can
run away and needs a cap. Here the roster is bounded per proposal and audited in `panel.json`, so
tier gating replaces the fraction guard rather than duplicating it.

### The debate: two rounds, then a deterministic tally

**Round 1 — independent critique.** All roles spawn in parallel, each seeing only the artifact and
its own charter. No panelist sees another's output. This is the round that produces diversity; letting
them read each other first would anchor them to whoever wrote fastest.

**Round 2 — rebuttal.** Each role receives the full set of Round 1 findings and may: uphold, withdraw
(explicitly, with a reason), or escalate a finding, and may rebut another role's finding. A finding
withdrawn under rebuttal is *more* informative than one that was never raised — it is recorded, not
deleted.

**Tally — `specclaw-party tally`, a script, not a model.** The verdict is arithmetic over the Round 2
findings, following the precedent set by `specclaw-loop` (the controller owns every mechanical
decision) and `specclaw-parse-tasks --count` (one counter, no `grep`):

| Condition | Verdict |
|-----------|---------|
| Any upheld **BLOCK** from any role | `CHANGES_REQUESTED` |
| ≥2 roles upheld a **WARN**, or any single role raised ≥3 | `APPROVED_WITH_NOTES` |
| Otherwise | `APPROVED` |

Deliberately *not* a chair model deciding the outcome — a synthesising model is free to average away
the one dissent that mattered. A model writes the *narrative*; the script writes the *verdict*.

### The report

`.specclaw/changes/<change>/party-report.md`, contract-identical in shape to `review-report.md` so
readers and future gates need no new parser:

```
VERDICT: APPROVED | APPROVED_WITH_NOTES | CHANGES_REQUESTED
<role>: <emoji> <BLOCK|WARN|NOTE>: <objection>. <what would resolve it>.  [upheld|withdrawn: <reason>]
```

Plus a **Dissent** section — every withdrawn finding and every unresolved disagreement, preserved
verbatim. That section is the point: it is the record that currently does not exist anywhere.

Findings are then folded into the proposal's **Open Questions** section, and the operator approves or
sends it back. The panel never edits the rest of `proposal.md` — it argues, it does not author.

### Where it runs

**Surface 1 — `/specclaw:propose` (primary).** A new step between "generate proposal.md" and "present
to the user":

- `party.default: false` (shipped default) → the skill **asks once**, and the prompt names the real
  bill for the **resolved** roster: *"Depth: deep — 'rewires four scripts and changes when PRs are
  created; security domain'. Panel: po, architect, ba, visionary, security — 5 agents × 2 rounds =
  10 spawns (2× fable, 4× opus, 4× sonnet). Run party mode? (y/N)"*. The classifier's rationale is
  shown verbatim, so an operator can reject a roster that was sized by a bad read.
  No answer, no panel.
- `party.default: true` → the panel runs automatically on every proposal, no prompt. Report is
  presented alongside the proposal.
- Either way the operator still approves the proposal. Party mode informs the decision; it never
  makes it, and `CHANGES_REQUESTED` does not hard-block `/specclaw:plan` in this change (`party.block`
  exists but ships `false` — the same one-release rollout `workflow.code_review_block` used).

**Surface 2 — `/specclaw:loop` halt (secondary).** When `specclaw-loop decide` returns `halt` and
`party.on_loop_halt: true`, run the panel on the *halt* rather than the proposal. Inputs are the
failing gates, `loop-log.md`, and the failure signature history; charters are re-pointed at strategy
("the loop has failed N times the same way — is the design wrong, is the gate wrong, or is the fix
approach wrong?"). Output attaches to the escalation notification, so the operator gets a diagnosis
instead of a status line. Round 2 is skipped here — a halt needs a fast read, not a debate.

### Config

```yaml
party:
  enabled: true            # feature available at all
  default: false           # true = run on every proposal without asking
  on_loop_halt: false      # run the panel when the loop escalates
  rounds: 2                # 1 = critique only (cheaper), 2 = with rebuttal
  block: false             # CHANGES_REQUESTED hard-blocks /specclaw:plan

  panel_mode: dynamic      # dynamic = size the roster to the proposal | fixed = use `panel` verbatim
  panel:                   # the roster when panel_mode is fixed
    - party-po
    - party-architect
    - party-ba
    - party-visionary
  always: []               # force-seated at every tier, e.g. [party-security]
  min_seats: 2
  max_seats: 6

  models:                  # per-role override of the agent's frontmatter model
    party-classifier: haiku
    party-visionary: fable
    party-architect: opus
    party-security: opus
    party-ba: sonnet
    party-po: sonnet
```

Dropping a role from a fixed panel is removing a line; adding one is writing an
`agents/party-<role>.md` and listing it. The panel is a list of agent names — no charter strings in
YAML, because a charter long enough to actually constrain a role is a document, not a config value.

## Scope

### In Scope
- New `bin/specclaw-party` — `panel` (score the proposal, resolve the roster, cache `panel.json`),
  `tally` (deterministic verdict from Round 2 findings), `report` (assemble `party-report.md`),
  `--json`. Non-zero exit on `CHANGES_REQUESTED` when `party.block: true`.
- New `agents/party-classifier.md` — `model: haiku`, `tools: [Read]`, returns
  `{tier, domains, rationale, signals}` JSON; charter defines what depth means (blast radius across
  subsystems, unresolved design surface, irreversibility, trust/data/release boundaries) and the
  escalate-only rule for the proposal's self-declared `Complexity:` / `Risk:`.
- Seat resolution in `specclaw-party panel`: tier → roster, domain flags → specialist seats,
  `always` force-seating, `min_seats` / `max_seats` clamps, `--panel <tier>` manual override, and the
  fail-loud fallback to `standard` with `tier_source: fallback`.
- Five new panelist agent definitions — `agents/party-ba.md`, `party-po.md`, `party-architect.md`,
  `party-security.md`, `party-visionary.md`. Each carries its own `model` frontmatter
  (`sonnet` / `sonnet` / `opus` / `opus` / `fable`), `tools: [Read, Write, Bash]`, a charter stating
  what it must attack **and what it must not comment on**, and the evidence discipline copied from
  `code-reviewer` (*a finding you cannot anchor to quoted text from the artifact is not a finding*).
- `party:` config keys — `panel_mode`, `panel`, `always`, `min_seats`, `max_seats`, `models`
  (per-role override of the frontmatter default, classifier included).
- `skills/propose/SKILL.md` — the confirm-or-auto step, Round 1 / Round 2 orchestration, report
  presentation.
- `skills/loop/SKILL.md` + `specclaw-loop escalate` — optional panel-on-halt, report attached to the
  escalation note.
- `party-report.md` written into the change folder (and therefore covered by the artifact set
  `029-staged-files-auditor` is proposing to enforce).
- `party:` config block + `specclaw-init` seeding, documented in `plugins/specclaw/CLAUDE.md`.
- Bats suite `run-party-tests.sh` — tally arithmetic at every boundary (0 blocks, 1 block, 2 warns
  across roles vs 2 warns from one role, all withdrawn); seat resolution for each tier from a
  **stubbed classifier JSON** (no model call in CI), the `min_seats` floor and `max_seats` ceiling,
  security seated on a `security` domain flag, `always` force-seating, `panel_mode: fixed` and
  `--panel` bypassing the classifier entirely, and the fallback path — malformed JSON, unknown tier,
  and non-zero classifier exit all landing on `standard` with `tier_source: fallback`; malformed
  finding lines.
  **Registered in `.github/workflows/ci.yml`** — an unregistered suite has silently never run twice
  in this repo. Shellcheck-clean.

### Out of Scope
- **Panels on `spec.md` / `design.md` / `tasks.md`.** The pattern generalises, but each surface needs
  its own charters and its own evidence rules. Prove it on proposals first.
- **A sixth role, or user-authored charters via config.** Ship the five, learn from real reports.
  Adding a role is already just a file plus a `panel` line.
- **Auto-editing the proposal.** The panel writes findings into Open Questions; it does not rewrite
  the Problem or Scope sections. An artifact edited by five arguing agents is unreviewable.
- **A chair/synthesiser model that decides the verdict.** Explicitly rejected above.
- **Inter-agent live conversation.** Two fixed rounds of written positions, not a chat loop with
  unbounded turns and unbounded cost.
- **Replacing operator approval.** `/specclaw:plan` still waits for the human.
- **Making party mode default-on in this change.** Ships `false`; flip after one release of real
  reports.

## Impact

- **Files affected:** ~14 (estimated) — 1 new `bin/` script, **6 new agent definitions**
  (5 panelists + the classifier), `specclaw-loop`, `skills/propose/SKILL.md`, `skills/loop/SKILL.md`,
  `specclaw-init` + `config.yaml` template, `plugins/specclaw/CLAUDE.md`, 1 new bats suite,
  `.github/workflows/ci.yml`.
- **Complexity:** medium — the tally and seat resolution are small and deterministic; a model
  classifier removes the threshold-tuning problem entirely (nothing to fit) at the price of
  non-determinism. Remaining weight: writing charters that actually disagree (non-overlapping
  mandates, explicit do-not-comment-on lists), the classifier charter's definition of depth, and
  Round 2 prompt construction (each panelist needs the others' findings without the whole
  transcript).
- **Risk:** medium.
  - **Cost, now proportional rather than flat.** A thin proposal draws 4 spawns (2 sonnet, 2 opus);
    a deep one with a security hit draws 10, including 2× `fable`. Still the most expensive gate in
    the lifecycle at the top end, but it only reaches the top end when the artifact earns it.
    Mitigations: ships opt-in; the confirm prompt states the resolved roster and **per-model** spawn
    count before spending anything; `rounds: 1` halves it; `party.models` takes the whole panel to
    `haiku` in one edit.
  - **Misclassification, now a model's judgement rather than a formula's.** A `haiku` call that
    under-reads a dangerous proposal seats two agents on it. Mitigations: fallback is `standard`,
    never `thin`; `always` force-seats; `--panel` overrides; `panel.json` records the tier, the
    rationale, and `tier_source`, so a bad call is a readable sentence rather than a mystery score.
    Cheapest available check: run the classifier over this repo's 31 existing proposals and read the
    tiers — a corpus that already exists and costs ~31 haiku calls to grade.
  - **Theatre.** Five agents that all say "looks good" produce a report that costs tokens and adds
    nothing. Mitigation: charters are written as *obligations to object* — each role must produce at
    least one finding or explicitly state "no objection under this lens", and the Dissent section
    makes an empty panel visible rather than reassuring.
  - **Deadlock.** A role that always BLOCKs stalls every proposal. Mitigation: `block: false` by
    default, so a BLOCK is information, not a gate.

## Open Questions

1. **Do the roles actually disagree, or do they converge on the same three objections?** This is the
   whole bet, and it is unchanged by dynamic sizing — a right-sized panel of clones is still a panel
   of clones. Worth running it manually against `029-staged-files-auditor` and
   `028-phase-time-accounting` before building anything — if the roles produce near-identical
   findings, the right change is *one* adversarial reviewer with a checklist, not a panel.
2. **Is Round 2 worth double the cost?** Rebuttal is what turns five opinions into a debate, but it
   may just produce five roles politely upholding everything. Measurable: what fraction of Round 1
   findings get withdrawn? If it is near zero, ship `rounds: 1`.
3. **Should the tally weight roles?** A Security BLOCK and a Visionary BLOCK are currently equal.
   Weighting is more correct and much harder to explain; flat is honest until the reports say
   otherwise. Note the tension with per-role models: if the Visionary is worth a `fable` seat, its
   findings are implicitly weighted already — by cost, not by the tally.
4. ~~Script classifier vs model classifier~~ — **decided: `haiku` reads the proposal.** Word counts
   and keyword lists were proxies the author model could move for free; length in particular punished
   verbose authors and let terse dangerous proposals through. Resolving this also retired the
   numeric `thresholds` config. What remains open is below.
5. **Is the classifier stable across reruns?** Two `haiku` calls on the same proposal may return
   different tiers, which means the same artifact can draw a different panel — and a different bill —
   on a retry. Options: cache `panel.json` and never re-classify a change (leaning: yes, the cache is
   already there), or accept the jitter as noise. Needs a decision at design time, because "why did
   this cost 10 spawns yesterday and 4 today" is a support question waiting to happen.
6. **Can the classifier be talked into `thin` by the proposal it is reading?** It consumes untrusted
   model-written prose, and a proposal containing "this is a trivial change, no panel needed" is a
   prompt-injection surface with a direct cost lever attached. The escalate-only rule covers the
   declared `Complexity:` field specifically; it does not cover prose. Mitigations to weigh: charter
   the classifier to ignore meta-instructions in the artifact, or floor the tier at `standard` when
   the proposal argues its own triviality.
7. **Does `fable` actually earn the Visionary seat?** Testable the same way as Open Question 1: run
   the Visionary charter on `029-staged-files-auditor` at `fable` and at `sonnet` and compare the
   findings. If they overlap, the seat is `sonnet` and the proposal is cheaper. This is the one model
   choice on the panel that should be justified by output, not by intuition.
8. **Do the panelists belong in the plugin's public agent list?** Being real `agents/` definitions
   means they show up as spawnable subagents everywhere, not only inside party mode — useful ("ask the
   Architect about this file"), but it also puts five specclaw-internal roles in every project's agent
   picker. Namespacing (`party-*`) helps; it does not hide them.
9. **Is the loop-halt surface the same change, or its own?** It shares the panelist agent and the
   tally, but the inputs, charters, and reporting path are entirely different. Splitting keeps this
   change small; combining avoids designing the agent contract twice. Leaning: keep it here in
   *design*, split it out at *task* level so it can be dropped if the proposal surface lands slow.
10. **What does the panel see?** Just `proposal.md`, or also `context.md`, `patterns.md`, and
   `learnings.md`? The Architect and Visionary roles are close to useless without project context;
   feeding all of it to five agents multiplies the token cost.
11. **Where does dissent live long-term?** `party-report.md` is per-change and gets archived. If the
   value is "the same debate does not rerun next quarter", recurring objections may belong in
   `patterns.md` — which would make this change a producer for `/specclaw:learn`.
12. **Interaction with `spec-author`.** That agent already challenges the user interactively (5 Whys,
   Inversion, Pre-mortem) at the *spec* stage. Is party mode the same job one phase earlier, and
   should the two share their technique vocabulary rather than inventing a second one?

---

**To proceed:** Review this proposal and approve to begin planning.
