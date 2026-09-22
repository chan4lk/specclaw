# Rebuild Workflow: connecting analysis to the delivery lifecycle

A recipe for rebuilding an existing (possibly legacy) application as a
faithful re-implementation in a new stack, using SpecClaw's analysis
commands (`bf-analyze`, `bf-architecture`, `bf-domain`) together with the ordinary
`propose → plan → build → verify → pr` lifecycle. Where a project chooses to
redesign its interface rather than reproduce it (`SQ-013` = `REINTERPRET`),
nothing in the new repo is built until a named client stakeholder has approved
that redesign screen by screen — see Step 4c. Nothing in this recipe
modifies `propose`, `plan`, `build`, `verify`, `pr`, or their bin
scripts/agents — it is entirely configuration plus one new read-only
command, `/specclaw:bf-rebuild-plan`.

## The gotcha, up front

**`git add` the analysis documents before anything else in this recipe
works.** `specclaw-discover-context` — the mechanism `plan`/`build`/`verify`
use to pull grounding documents into an agent's context — enumerates
candidate files via `git ls-files`, not a plain filesystem walk. A file
`bf-analyze`/`bf-architecture`/`bf-domain` wrote to `.specclaw/analysis/` but that was
never staged is invisible to discovery, **even if you've pinned it** (see
Step 3). Staging is enough — you don't need to commit:

```bash
git add .specclaw/analysis/*.md
```

Re-run this after every `bf-analyze`/`bf-architecture`/`bf-domain`/`bf-rebuild-plan`
run that produces a new or updated document.

## Step 1 — Produce the analysis documents

```
/specclaw:bf-analyze
/specclaw:bf-architecture
/specclaw:bf-domain
```

These write `.specclaw/analysis/codebase-report.md`, `architecture.md`,
`domain-model.md`, and `functional-spec.md`. Read-only, no lifecycle gate —
run them in any order, any number of times (each re-run archives the prior
version into `.specclaw/analysis/archive/`).

## Step 2 — Stage them

```bash
git add .specclaw/analysis/*.md
```

## Step 3 — Pin them for the lifecycle

Add the four paths to `context.pin` in `.specclaw/config.yaml` (a
commented-out example ships in the config template — uncomment and adjust):

```yaml
context:
  pin:
    - .specclaw/analysis/codebase-report.md
    - .specclaw/analysis/architecture.md
    - .specclaw/analysis/domain-model.md
    - .specclaw/analysis/functional-spec.md
```

`specclaw-discover-context` checks `context.pin` **before** its default
directory exclusions — including the one that normally skips `.specclaw/`
entirely — so pinned analysis documents bypass that exclusion and are
force-ranked highest priority. Once pinned (and staged, per the gotcha
above), `/specclaw:plan`, `/specclaw:build`, and `/specclaw:verify` all pick
them up automatically, with no change to any of those three skills.

**Size the shared budget.** All four documents are pinned at top priority
and are emitted into the digest first, ahead of README/CLAUDE.md/other
`docs/*` discovery, within `context.max_lines` (default `3000`). For a real
legacy codebase they can easily be large enough to consume the whole
budget on their own, silently crowding out everything else discovery would
normally surface. Size `max_lines` to the pinned total plus headroom:

```bash
wc -l .specclaw/analysis/*.md | tail -1   # pinned total
```

Set `context.max_lines` to that total plus roughly `3000` for other repo
docs (the original default), e.g. if the four documents total 4,200 lines,
set `max_lines: 7200`. `specclaw-discover-context` never drops a file
silently regardless of the number you pick — every truncated or dropped
document is named in a footer comment in its output — so if you see
docs missing after this, that footer tells you exactly which and why.

## Step 4 — Generate the rebuild backlog

```
/specclaw:bf-rebuild-plan
```

Reads the four analysis documents and writes
`.specclaw/analysis/rebuild-backlog.md`: an ordered list of individually
proposable features, each naming the `functional-spec.md` capability it
covers, the `domain-model.md` rules/entities that form its acceptance
basis, its dependency on earlier items, and a "Verification inputs needed"
field (see Fidelity limitation, below). It also includes a coverage check
confirming every functional-spec capability is accounted for.

If any of the four analysis documents is missing, `bf-rebuild-plan` stops and
names exactly which one(s) plus the command that produces each — it never
attempts a partial backlog.

**Optional but recommended: run `/specclaw:bf-clarify` and `/specclaw:bf-baseline`
first.** Neither is required — `bf-rebuild-plan` degrades gracefully without
them, naming what's missing in its status header — but when
`.specclaw/analysis/clarifications.md`/`decisions.md` and
`.specclaw/baseline/manifest.json`/`scenarios.md` are present, every backlog
item also gets a computed **Gate** (blocked by an unanswered clarify
question, at risk from a non-blocking one, or clear) and **Verification**
state (a captured golden-master fixture exists, one is designed but not yet
captured, the behavior is provably unreachable in the legacy app, or no
baseline work has touched these rules at all) — turning the backlog from a
static acceptance-basis list into a live readiness signal.

`bf-rebuild-plan` creates **nothing** under `.specclaw/changes/` and calls
**no** lifecycle command. Stage its output too:

```bash
git add .specclaw/analysis/rebuild-backlog.md
```

**The backlog is living state after the first run.** A second bare
`/specclaw:bf-rebuild-plan` refuses to regenerate it (to avoid destroying
in-flight Gate/Verification status, struck/deferred items, or a status note
a human typed into an item). Run `/specclaw:bf-rebuild-plan --refresh` instead
— it recomputes Gate/Verification for every item, applies any newly
recorded decisions (striking, deferring, or reshaping items; appending
genuinely new ones), and ends with a change report naming what became
unblocked or verifiable, what was struck/deferred/revised/added, and the
single recommended next item to propose. `BL-###` item ids are permanent
across every refresh, never renumbered.

## Step 4b — Optional: UI fidelity capture

**Skip this entire step unless the rebuilt interface has to resemble the
legacy one.** `/specclaw:bf-clarify`'s standard bank asks the question either
way — `SQ-013`, "UI fidelity policy for this rebuild?", with exactly three
answers:

| Answer | Means |
|---|---|
| `FAITHFUL` | Reproduce the legacy layout structure and colour theme exactly, within the target platform's own rendering norms. |
| `THEME-ONLY` | Keep the colour palette / branding tokens; the layout is reinterpreted for the target platform. |
| `REINTERPRET` | New design; the legacy UI is reference material only. |

Answer `REINTERPRET` and **no fidelity requirement is attached to any backlog
item** — but you are not done: see Step 4c below. The legacy UI becomes
reference material, which settles what the rebuild must *look* like and settles
nothing about what it *will* look like. Somebody still has to agree to the new
design, and `REINTERPRET` is the answer that makes that agreement the project's
own responsibility rather than the legacy screenshots'.

The proposed default is `REINTERPRET` precisely *because* it is the
least-work reading: it has to be chosen deliberately rather than assumed
silently, which is what would otherwise let a rebuild quietly discard an
interface its users know by heart.

Answer `FAITHFUL` or `THEME-ONLY` and the workstream activates:

```
/specclaw:bf-ui                       # in the legacy repo, after bf-domain
  → .specclaw/ui/ui-inventory.md          one section per screen, permanent SCR-###
  → .specclaw/ui/design-tokens.json       colour/typography/spacing, permanent TK-
  → .specclaw/ui/screenshot-checklist.md  a human work order

  ... a human runs the legacy app and captures the PNGs into
      .specclaw/ui/screens/, per the checklist's exact filenames ...

/specclaw:bf-ui --record              # hashes them into ui-manifest.json
/specclaw:bf-rebuild-plan --refresh   # attaches SCR/TK grounding to items
```

Then, once a change is built in the new repo:

```
/specclaw:bf-ui --checklist <change-name>
  → .specclaw/changes/<change>/ui-review.md
```

A named human fills in that file's rows and commits it with the PR, next to
the replay evidence package. Together they are the change's complete fidelity
record: mechanical proof for behaviour, signed human review for appearance.

**`--checklist` works under `REINTERPRET` too, against a different reference.**
There is no legacy appearance to reproduce, so instead of a legacy screenshot
each row cites the **approved prototype screen** from Step 4c — by `PS-###` and
hash, with the name and date of the stakeholder who signed it off — and the rows
are the review points recorded when that screen was briefed. One row per review
point, each naming the `DR-###` or workflow step it protects. A change whose
screens are not approved refuses to generate a review at all, because a
signature against an unapproved design records agreement nobody gave. With no
prototype copied into the repo, the command refuses exactly as it always did.

**No specclaw command ever runs the legacy app, takes a screenshot, or judges
whether two screens look the same** — the same boundary `/specclaw:bf-baseline`
draws around fixture capture, for the same reason. And UI is never a
golden-master seam: `/specclaw:bf-replay` compares no screenshot and its
verdict says nothing about appearance (it gains one informational footer line
saying so). Do not read `.specclaw/ui/` as a promise of pixel-identity; read
it as the reference a human checks against, on the record.

If the policy is decided but the `.specclaw/ui/` artifacts don't exist,
`/specclaw:bf-rebuild-plan` says so loudly — one warning naming every missing
artifact, with every screen-bearing item held at `OPEN QUESTIONS`. It will not
quietly proceed as though the UI requirement had been dropped.

## Step 4c — Approve the redesign before anything is built (REINTERPRET only)

**Skip this entire step unless `SQ-013` is decided `REINTERPRET`.** Under
`FAITHFUL` or `THEME-ONLY` the rebuilt interface is held to the legacy one and
Step 4b already covers it. Under `REINTERPRET` it is not held to anything —
and *that* is the problem this step exists for.

A redesign nobody approved is not a smaller risk than a bad reproduction; it is
a larger one, and it surfaces later. The moment approval is cheap is **before
the application exists**. Afterwards, an approval is being asked for something
already built, and "the client didn't like it" costs a rebuild of the rebuild.

So under `REINTERPRET` this step is **mandatory**, and the whole new-repo side
is locked behind it:

```
/specclaw:bf-prototype                # in the legacy repo, after bf-blueprint
  → .specclaw/prototype/prototype-brief.md   one section per redesigned screen
  → a permanent PS-### per screen, from an append-only registry
  → hands the brief to the skill named in config.yaml's prototype.skill

  ... that skill builds a throwaway prototype in the decided stack ...
  ... a human puts it in front of the client, screen by screen ...
  ... and captures one screenshot per PS-### into .specclaw/prototype/screens/ ...
  ... then a NAMED stakeholder writes their verdict into prototype-approvals.md ...

/specclaw:bf-prototype --record       # hashes it all, computes the status of
                                      # every screen, prints the gate line
```

The last command prints exactly one of:

```
PROTOTYPE: READY
PROTOTYPE: NOT-READY (PS-003 (STALE), SCR-007 uncovered)
```

**`PROTOTYPE: READY` is the ticket into Phase B.** `NOT-READY` means go and get
the named screens approved or the named questions decided. Never copy early,
never bootstrap anyway — and there is no need to enforce that by discipline,
because a `NOT-READY` manifest copied into the new repo is inert and refuses
everything.

### specclaw does not build the prototype

It writes the brief and owns the records. A separate UI/prototype skill —
whichever one you name in `config.yaml`'s `prototype.skill` — builds from it.
There is no UI generator in this plugin and there is not going to be one.

### The stack is decided, not chosen

The prototype is built in **exactly** the frontend framework *and* language the
project decided, each resolved from the decision record with its own citation:

| Value | Question | If undecided |
|---|---|---|
| Framework | `SQ-006` | `/specclaw:bf-prototype` stops naming `SQ-006` |
| Language | `SQ-015` | It stops naming the language, with the route to answer it |

> **Framework known, language not? The command stops.** A framework name
> decides a framework and nothing else. Raise the language as a question and
> decide it by name — the pipeline never picks one for you, not from the
> framework's convention and not from the legacy app. One answer can settle
> both: write `SQ-006` as `<framework> (<language>)`, with the language a
> single bare word.

Building in the real target stack is the point: the client approves component
behaviour they will actually get, and the production team can read the result
as a reference. It does not make the prototype production code.

### A redesign that changes behaviour is a question, not a design choice

Anything the redesign would change about what the system *does* — a required
field removed or added, a validation altered, a workflow merged or split, a
status transition changed, a screen retired — is raised as a `PQ-###` rather
than built. Until a human decides it, the affected screen cannot be computed
approved, so the prototype cannot reach `READY`:

```
/specclaw:bf-prototype        → behaviour change found → PQ-###
/specclaw:bf-clarify          → promotes it to a CQ (Blocking: yes)
  ... a human decides it ...
/specclaw:bf-clarify --resolve
/specclaw:bf-rebuild-plan --refresh → /specclaw:bf-blueprint → re-run bf-prototype
```

The `PS-###` keeps its id throughout, and the marker clears itself. Once
decided, the change surfaces in `/specclaw:bf-replay` as
`DIVERGES — SANCTIONED (CQ-###)` through the path that already exists.

### The two things specclaw will not do for you

**Capturing the screenshots**, and **recording the approvals**. Both are human
work, for the same reason golden-master fixtures are:
`prototype-approvals.md` is written by a person and by no agent or script,
ever. One row per screen:

```
| PS-001 | APPROVED | Mira Costa | 2026-09-16 | <tree_hash from the --record run they reviewed> |
```

That hash is what binds an approval to a specific prototype. Edit the prototype
afterwards and the screen reads `STALE` — the signature on file no longer
describes what exists, and it has to be given again.

### Readiness is measured against the backlog

Not against the legacy screen inventory. A rebuild deliberately leaves screens
behind, and a gate demanding an approved redesign for every legacy screen would
be unmeetable on any real project — so it would get switched off, which is
worse than not having it. A screen blocks only if an in-scope, active backlog
item renders it. Screens the client scoped out are **listed with their reason**
rather than dropped silently.

An *undecided* `CQ` retires nothing. A screen dropped on an unanswered question
is exactly the silent scope cut this step exists to surface.

### The prototype is thrown away

Only `prototype-map.md`, `prototype-manifest.json` and `screens/` travel to the
new repo (Step 6). The prototype application never does — it is not a
foundation, and `/specclaw:bf-bootstrap --adopt` refuses it by hash, by name.

## Step 4d — Migrate and accept one module at a time

`/specclaw:bf-domain` also writes `.specclaw/analysis/module-map.md`: the
`MOD-###` migration units the system's entities, rules, services and screens
group into, each with its owned vs referenced-but-not-owned entities and its
dependencies on other modules. The hierarchy is
`MOD-### → BL-0## → DR-### → GM-###`. Modules are a **selection dimension** over
the one shared corpus — there is still one manifest, one backlog, one
`fixtures/` directory, and nothing is split per module.

**Confirm the map before you sequence a migration on it.** It is agent-proposed:
its `**Status:**` line reads `PROPOSED` until a human edits it to
`CONFIRMED by <name>, <date>`. Nothing is blocked by an unconfirmed map — every
command runs and says on its own face that the grouping is unconfirmed — but the
boundaries become the shape of the whole rebuild, so they are worth an hour of
review. An ambiguous boundary is never assigned silently: it becomes a typed
pending question for `/specclaw:bf-clarify` and the item is placed
provisionally.

Then work one module at a time:

```
/specclaw:bf-rebuild-plan --refresh --module MOD-002   # plan just this module
/specclaw:bf-baseline --module MOD-002                 # design its scenarios
/specclaw:bf-baseline --harness --module MOD-002       # extend the harness
#   ... a human runs the harness and captures fixtures ...
/specclaw:bf-baseline --record                         # whole-corpus, as always
/specclaw:bf-replay --module MOD-002                   # accept the module (in the NEW repo)
```

Each `--module` step leaves every other module's items, scenarios, generated
tests, coverage lines, and human-added notes untouched. `--record` stays
whole-corpus: the manifest is one document, and a module tag is a field on a
fixture, not a separate file.

**Watch the shared flows.** A scenario whose rules span two modules is tagged
with both, is selected by both modules' replay runs, and counts toward both in
the report's module rollup — which always states how many of a module's fixtures
are shared and with which others. That is deliberate: a shared fixture is the
flow that breaks when one module is rebuilt in isolation, so a module PASS that
quietly excluded it would be a false verdict. Read the rollup, not just the
overall verdict, before calling a module accepted.

`.specclaw/analysis/module-status.md` (regenerated by every
`/specclaw:bf-rebuild-plan` run) is the one-screen view of where each module
stands: items planned, scenarios captured, latest module-scoped replay verdict,
open questions. It is a status view — no number in it says a module is *done*,
because specclaw records no built state for a backlog item.

`/specclaw:bf-status` is the other half of that picture, and answers the
question the per-module table cannot: **which of these commands have I actually
run, and what comes next.** One row per `bf-*` phase, every open item holding a
phase back, and a single recommended next command. It writes nothing at all and
runs in a second, so it is the cheapest way to pick a rebuild back up after a
break or hand it to someone else. Where `module-status.md` asks "how far along
is MOD-002", this asks "where is the rebuild".

## Step 4e — Bootstrap the target foundation (in the NEW repo)

**This step runs once per rebuild repo, after the Phase B copy set (Step 6) is
in place and before the first `/specclaw:propose`.** Everything above happens in
the legacy repo; this is where the target application starts existing.

**Under `REINTERPRET`, this step does not start until Step 4c printed
`PROTOTYPE: READY`.** Bootstrap gains an eighth precondition beside its seven
required decisions — a copied `prototype-manifest.json` recording
`prototype_ready: true`, `screens/` present with every screenshot hash
re-verified, and the manifest's policy, framework and language still matching
this repo's own decision record. Anything it cannot read, it treats as not
approved and scaffolds nothing:

> REINTERPRET project: prototype not approved. Run bf-prototype --record in the
> legacy repo until it prints PROTOTYPE: READY, then copy prototype-map.md +
> prototype-manifest.json + screens/ together and re-run.

This applies to every mode including `--adopt`, which additionally refuses a
tree hashing identically to the approved prototype: *"This is the approved
prototype, not a production foundation. Scaffold fresh."* Non-`REINTERPRET`
repos see none of this.

```
/specclaw:bf-bootstrap
```

It reads the architecture the rebuild has **already decided** — `decisions.md`'s
`SQ`/`CQ` answers plus any accepted ADR in the new repo — and scaffolds the
skeleton for it: app shell, routing shell, API client, solution/project layout,
DI, configuration, CORS, error-handling conventions, ORM and database
connectivity, migrations infrastructure, test-project structure for both sides,
theme plumbing, and exactly one health-check endpoint to prove the wiring works.
Then it smoke-tests all of that, checks the result against a foundation-only
gate, and records `.specclaw/bootstrap/bootstrap-manifest.json`.

**Why this step exists.** Before it, nothing owned the target application's
existence. Every `bf-` analysis command is read-only and runs in the legacy
repo; `bf-rebuild-plan` writes one document; `bf-replay` assumes the rebuild's
real service and entity files are already there. The only writer of application
source was `/specclaw:build` — which is scoped to *one change* — so the first
backlog item proposed inherited responsibility for inventing the skeleton, and
inherited it *invisibly*, because nothing in its spec or tasks said so. On a
real rebuild that produced an ASP.NET Core API, EF Core, PostgreSQL and passing
backend tests for a screen-bearing patient-grid item, and no React application
at all.

**It implements no backlog capability.** No Sign In, no patient grid, no
register-patient, no payments — not a stub of one, not a placeholder screen
named after one, not an endpoint returning fixture data. Each belongs to its own
`BL-###`. The agent declares a census of everything it created (every file with
a purpose, every route, every screen, every token group), and a gate checks that
census against a closed, stack-neutral vocabulary: a file declared `capability`,
a route beyond the health check, or a `DR-###`/`BL-###`/`SCR-###` id anywhere in
the scaffold each fail it. That gate is a declared-census check plus id greps —
it cannot prove the absence of capability logic, and says so rather than
implying otherwise.

**It consumes decisions; it never makes them.** Seven are required and have no
default anywhere: `SQ-001` (platform), `SQ-002` (database), `SQ-003` (hosting),
`SQ-004` (auth approach — it decides whether the shell has an auth *boundary*,
never that auth is implemented), `SQ-006` (UI framework), `SQ-013` (UI fidelity)
and `SQ-014` (backend stack). An unresolved one is a **loud stop naming the
exact id**. Answer it with `/specclaw:bf-clarify` (then `--resolve`) and re-copy
`decisions.md`. A question declared *Not applicable* in `clarifications.md` is an
answer too — a client-only rebuild genuinely has no backend stack to choose.

**Stack-agnostic, purely dynamic.** There is no per-stack scaffold template in
the plugin and there will not be one; the skeleton is generated per run for
whatever stack the decisions name, exactly as the baseline harness and the
replay tests are.

**Re-running is safe.** A healthy recorded foundation is a no-op. One with a
pillar recorded absent or failed is gap-filled — and only those pillars. If the
repo already contains an application but no manifest, it **stops and asks**
rather than scaffolding over somebody's work; `--adopt` smoke-tests and records
what is already there.

From here on, `/specclaw:propose` checks this state mechanically and refuses to
draft a proposal without it:

> Target rebuild foundation has not been created. Run `/specclaw:bf-bootstrap`
> first.

**Under `REINTERPRET`, `/specclaw:propose` checks the prototype too** — twice,
for two different reasons. Once for the whole repo, on *every* change rather
than only screen-bearing ones, because a repo bootstrapped while the redesign
was approved and whose approval was later withdrawn has an unapproved design
underneath everything now being proposed. And once per item:

> Prototype screen(s) not approved for BL-0NN: SCR-004 → PS-003 (STALE),
> SCR-007 → (no prototype screen). Re-approve, re-record, re-copy.

An item that renders no screen passes on the whole-repo check alone.

That gate is inert on any project with no `rebuild-backlog.md`, so nothing
greenfield ever sees it. The one honest false positive — proposing an ordinary
change inside the **legacy** repo, which also carries a backlog — is settled by
recording it once, explicitly:

```
/specclaw:bf-bootstrap --not-applicable "this is the legacy repo"
```

## Step 5 — Propose each backlog item yourself

`/specclaw:bf-rebuild-plan` does not, and will not, auto-invoke
`/specclaw:propose` — that would reintroduce the exact lifecycle coupling
this recipe deliberately avoids. Work through `rebuild-backlog.md` in the
order it gives you:

```
/specclaw:propose "<backlog item title>"
```

Because the analysis documents are already pinned (Step 3), the resulting
`/specclaw:plan` for each item is grounded in the same functional-spec
capability and domain-model rules the backlog item cited — no need to
re-paste analysis content into the conversation.

### Starting a module before its dependencies exist

The module graph is the **recommended** order, not a lock. Real migrations
routinely need to start somewhere the graph says isn't ready — a team frees up,
a stakeholder wants the flow they actually care about, the foundation module is
blocked on a decision. You can do that, deliberately and on the record.

When a proposed item depends on a *cross-module* item with no completion
signal, `/specclaw:propose` stops and asks — per dependency — how to stand in
for it: a **stub-interface**, **mock-data**, a **feature-flag**, or an
**item-split** (the honest non-stub option: ship the part that doesn't need the
dependency, and let the rest wait). "It is actually built" and "abort and
follow the recommended order" are always on the list too.

**The choice is always yours.** Nothing picks a strategy for you and there is
no default — the entry records your name and the date. That is the point: the
cost of a bypass isn't the stub, it's forgetting there was one.

**An item split is recorded separately, because it is a different kind of
thing.** The first three strategies *fake* a dependency: they produce an
`ST-###`, they can taint a verdict, and they are retired when the real module
lands. A split fakes nothing — it *defers real scope* — so it gets its own
`IS-###` entry in `.specclaw/analysis/item-splits.md`, never taints anything,
and completes rather than retiring. A stub asks "was the thing under test
real?"; a split asks "is this item even finished?", and answering that needs
fields an `ST-###` entry never had. See **Splitting an item** below.

Each stub choice becomes a permanent `ST-###` entry in
`.specclaw/analysis/module-stubs.md`, and from then on:

- the consuming backlog items carry `⚠ STUB-BACKED`;
- any `/specclaw:bf-replay` verdict for their fixtures says
  `(with active stubs: ST-###)`, in the report *and* in the retained evidence;
- `module-status.md` shows the module as `PASS*`, never a clean `PASSED`, and
  lists who is waiting on the real module.

**None of that changes a verdict.** A tainted PASS is still PASS with exit 0; a
tainted FAIL is still FAIL with exit 1. Taint qualifies a verdict's standing, it
never softens it.

To retire one: write `BUILT: <evidence>` into the real item's **Status notes**
block, re-run `/specclaw:bf-rebuild-plan --refresh` (its **Stub Retirement**
section prints the exact commands and who runs each), remove the stub code,
flip the entry to `RETIRING`, re-replay the consumers, and — only on a clean
run — flip it to `RETIRED` citing that run id.

Two things this deliberately will not do. It will not let you bypass a
**same-module** dependency: that is the item's own groundwork, and stubbing it
means stubbing part of what you are building. And it will not infer that a
dependency is done from prose — only a literal `BUILT:` line counts, because
guessing here silently skips the question that would have caught the gap.

### Splitting an item

An **item split** ships part of a backlog item now and defers the rest. It is
recorded as an `IS-###` entry carrying what shipped, what waits, which
`DR-###` rules each half covers, and what unblocks the remainder.

**Prefer a vertical slice.** A thin end-to-end capability — the grid renders,
calls a real endpoint, runs a real query against real data, and only the auth
integration waits — delivers something a user can open. A horizontal stack cut
(every layer below the UI ships, and the UI waits) produces an item that looks
nearly finished and delivers nothing anyone can use, with its acceptance basis
unmet and no fixture able to notice. That is not hypothetical: it is exactly
what happened when a screen-bearing patient grid was split to defer *auth* and
lost its entire frontend instead.

**The split you choose is the split that happens.** Two guards enforce it:

- **The rule partition.** What ships and what waits must together account for
  every `DR-###` in the item's acceptance basis, with no overlap and nothing
  left out. A rule in neither half is scope nobody owns, so nothing can later
  tell whether it shipped.
- **Layer removal.** Deferring the whole UI layer from a screen-bearing item is
  **refused** unless a named human confirms that consequence, stated in those
  terms: *"this would ship BL-010 with no user-visible part at all, and its UI
  acceptance basis (SCR-004, TK-001) would go unmet."*

From then on:

- the item renders `⚠ PARTIALLY BUILT` in `rebuild-backlog.md`, naming what is
  still deferred;
- `/specclaw:bf-replay --item BL-###` reports `(partial — split IS-###)`, names
  which of its fixtures cover built versus deferred scope, and states that the
  run **is not that item's acceptance**;
- `module-status.md` counts the module's partially built items, separately from
  its stub-tainted ones — a module can be entirely untainted and still be
  carrying items that are each missing a layer.

**None of that changes a verdict.** A partial `PASS` is still `PASS` with exit
0; a partial `FAIL` is still `FAIL` with exit 1. And a fixture pinning a
deferred rule is still replayed and still counts — excluding it would change
what the run fails on and hide a real regression behind a scope note. So a FAIL
among those is expected and explained; a **PASS among them is a surprise worth
investigating**.

**The split comes back on its own.** Write `BUILT: <evidence>` into each
blocked-until item's **Status notes** block; the next
`/specclaw:bf-rebuild-plan --refresh` flips the entry to `READY-TO-RESUME`
mechanically and says so. Then `/specclaw:propose BL-###` **resumes** rather
than restarting: it shows what was already built and the PR/replay evidence for
it, proposes only the remainder, and never re-asks about a dependency the split
already deferred. Only a clean `--item` run afterwards marks the split
`COMPLETE`, and the `⚠ PARTIALLY BUILT` marker then clears by regeneration.

The governing principle: **choosing item-split must never make implementation
history disappear.** If specclaw deliberately splits an item today, it must know
exactly what was completed and what remains when that item is resumed months
later.

## Step 6 — What to copy into the new repo (the Phase B copy set)

Steps 1–4d all run in the **legacy** repo (Phase A). `/specclaw:bf-replay` and
`/specclaw:bf-ui --checklist` run in the **new** repo (Phase B), and they need
the Phase A artifacts to be present there — they resolve a change to its
backlog item, its fixtures, and its screens by reading these files:

```
.specclaw/analysis/module-map.md              # MOD modules: names, deps, rule ownership
.specclaw/analysis/rebuild-backlog.md        # change → BL item → DR rules / SCR screens
.specclaw/analysis/domain-model.md           # DR rules, for coverage reporting
.specclaw/analysis/decisions.md              # sanctioning CQs; the SQ-013 UI policy
.specclaw/analysis/target-architecture.md    # the target blueprint (readability only)
.specclaw/baseline/scenarios.md              # GM scenario definitions + seam layers
.specclaw/baseline/seams.md                  # seam recommendations cited in remediations
.specclaw/baseline/error-map.md              # the project's semantic error vocabulary
.specclaw/baseline/manifest.json             # fixture roster + content hashes  ┐ always
.specclaw/baseline/fixtures/                 # the captured fixtures           ┘ together
.specclaw/ui/ui-inventory.md                 # SCR entries (FAITHFUL/THEME-ONLY only)
.specclaw/ui/design-tokens.json              # TK groups          (same)
.specclaw/ui/screenshot-checklist.md         # states + setup notes (same)
.specclaw/ui/screens/                        # captured PNGs      ┐ always
.specclaw/ui/ui-manifest.json                # their hashes       ┘ together
.specclaw/prototype/prototype-map.md         # the approval record    ┐ REINTERPRET
.specclaw/prototype/prototype-manifest.json  # statuses + review pts  │ only, and
.specclaw/prototype/screens/                 # approved screenshots   ┘ all three together
```

**Under `REINTERPRET`, copy the three prototype files only once
`/specclaw:bf-prototype --record` has printed `PROTOTYPE: READY`** — and copy
them together, for the same reason `screens/` and `ui-manifest.json` travel
together: the manifest records a hash per screenshot, and a manifest without
the files it hashes proves nothing at all.

Copying early is not dangerous, only useless: a manifest recording
`prototype_ready: false` is inert, and `/specclaw:bf-bootstrap` and
`/specclaw:propose` both refuse until a ready one replaces it. That is
deliberate — timing cannot be enforced on a manual copy, so it is enforced at
the first command in the new repo instead.

**Never copied, under any policy:**

```
.specclaw/prototype/app/                     # the prototype itself — thrown away
.specclaw/prototype/prototype-brief.md       # a legacy-side working document
.specclaw/prototype/prototype-approvals.md   # the human's signatures, kept where written
.specclaw/prototype/id-registry.json         # the PS-### allocator, legacy-side only
```

The prototype application never travels. It is built in the real target stack
so the client can approve realistic behaviour and the production team can read
it as a reference — which is exactly what makes it look adoptable — but it
fakes persistence and auth, carries sample data, and is structured to be thrown
away. `/specclaw:bf-bootstrap --adopt` refuses a tree that hashes identically
to it, by name. The production foundation comes from bootstrap's own scaffold
and nowhere else.

The review points a reviewer signs later live in the **manifest**, not the
brief, precisely so the new repo needs nothing from a document that is not
copied to it.

**`module-stubs.md`, `item-splits.md` and `.specclaw/bootstrap/` are not in the
copy set — they are *born* in the rebuild repo.** Bypasses and splits are chosen
at `/specclaw:propose` time, which runs where the changes live, so both
registries are created there by the first proposal that elicits one; the
bootstrap manifest is written by `/specclaw:bf-bootstrap`, which runs only in
the new repo. Nothing copies any of them from the legacy repo, and a rebuild
repo without a registry simply has no stubs and no splits — every reader treats
each as empty, silently.

**`target-architecture.md` travels for the same reason, and with the same limit.** It is the target blueprint `/specclaw:bf-blueprint` writes in the legacy repo — the one document that shows the shape of what is being built and what each part of it rests on, which makes it worth having open in the rebuild repo. Nothing computes from it: every decision it cites is already in `decisions.md`, and `/specclaw:bf-bootstrap` reads that file directly and would scaffold identically if the blueprint had never been generated. Re-copy it after any `--resolve` that answers a question it renders `PROVISIONAL`.

**`options-pack.md` is deliberately NOT in the copy set.** The client decision paper is a legacy-repo artifact: the decisions it elicits travel as `decisions.md` entries, which are already here, and a stale copy of the pack in the rebuild repo would show questions as pending that have since been answered.

**`module-map.md` travels too, but is not load-bearing for a verdict.** `/specclaw:bf-replay --module` selects fixtures from `manifest.json`'s own `module_ids`, never from the map — so a replay run works without it. What the map adds in the new repo is readability: the report's module rollup names each module, and `module-status.md` can be regenerated there. Copy it; if it is absent, rollups still compute and simply read as bare `MOD-###` ids.

**`error-map.md` is not optional.** It is the legacy app's own error vocabulary
— one `SCREAMING_SNAKE` code per business condition it can reject on, each
citing the legacy line that raises it. `/specclaw:bf-replay` maps the rebuild's
errors into *that* vocabulary rather than comparing raw exception type names,
which is what stops a framework change from reading as twenty behaviour
changes. Without this file in the new repo, no error can be mapped at all and
every rejection scenario lands as an unmapped code holding the run at
`PASS-PENDING-DECISIONS`. Nothing in the specclaw plugin contains a code; this
file is the only place they exist.

**The paired lines are paired for one reason: a hash without the file it
hashes, or a file without its recorded hash, proves nothing.**
`/specclaw:bf-replay resolve` already enforces this for fixtures — it refuses
to run if a selected fixture's recomputed sha256 doesn't match
`manifest.json`, because comparing against a half-copied or edited baseline is
worse than not comparing at all. `screens/` and `ui-manifest.json` follow the
same rule: copy them together, or the sha256 a reviewer is asked to confirm
in `ui-review.md` refers to nothing.

Re-copy after any Phase A re-run that changes them. The `.specclaw/ui/` lines
are needed only when the UI fidelity policy is `FAITHFUL` or `THEME-ONLY`;
under `REINTERPRET` the copy set is just the first eight lines, exactly as it
was before the UI workstream existed.

## Fidelity limitation

This recipe makes the functional spec's capabilities and the domain
model's rules the **acceptance basis** for each rebuilt feature — that is
what pinning plus the backlog's per-item references gives you. It does
**not** prove that the new implementation behaves identically to the
legacy system. True "same app" verification additionally requires:

- **Golden-master outputs** — recorded input/output pairs from the running
  legacy system, captured by a human, to diff the new implementation
  against. No amount of static analysis produces these.
- **External-format and DLL/COM semantics** — where the legacy app depends
  on a proprietary file format, an opaque DLL, or a COM component whose
  runtime behavior isn't recoverable from source alone, a human with
  domain knowledge of that dependency must supply it.

`rebuild-backlog.md`'s "Verification inputs needed" field exists to name
these gaps per item, not to imply they're already covered. Treat a backlog
item's acceptance criteria as necessary, not sufficient, for a truly
faithful rebuild.

## Approval limitation

Under `REINTERPRET`, Step 4c records that a named person approved each
redesigned screen, on a date, against a prototype whose exact contents are
hashed. That is a real and checkable fact, and it is deliberately a narrow one.

What the record does **not** establish:

- **That the approved design is good.** Approval is a human judgement about a
  human artifact. specclaw can prove who signed what and when; it has no
  opinion about whether they should have.
- **That the approver understood what they were approving.** Putting a working
  prototype in front of someone is a much better basis for that than a
  wireframe or a description — which is exactly why the prototype is built in
  the real target stack — but it is still not proof.
- **That the built application resembles the approved screens.** Nothing
  compares them mechanically. `/specclaw:bf-ui --checklist` asks a human to
  confirm it row by row against the approved screenshot, and that signature is
  the only evidence there is. UI stays excluded from the golden-master seam
  taxonomy under every policy, `/specclaw:bf-replay` compares no screenshot,
  and no specclaw command claims pixel-identity.

What it does establish is the thing that was previously missing entirely: that
the redesign was agreed **before** the application was built, by someone named,
and that nothing production-side started until it was. A behaviour change the
redesign proposed cannot pass through silently, because it becomes a question
that has to be decided rather than a design choice that gets built.

## Staleness limitation

`bf-rebuild-plan` does not check whether the analysis documents are stale
relative to the current source — it trusts each document's own "Date
analyzed" field and never diffs it against git history. If the codebase has
changed meaningfully since that date, re-run `/specclaw:bf-analyze`,
`/specclaw:bf-architecture`, and `/specclaw:bf-domain` before `/specclaw:bf-rebuild-
plan` so the backlog reflects the current code, not a stale snapshot.
