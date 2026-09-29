# Changelog

All notable changes to specclaw are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — teaching mode: syllabus guide (fork: Jayzilva/specclaw)

### Added
- **Syllabus guide (opt-in).** After the teaching assessment shows the level map,
  `/specclaw:teach` offers once to generate a study guide: one chapter per
  technology rated (a) or (b), each with why-it-matters-here, a mental model, a
  Mermaid diagram, core primitives in the project's own stack, a worked example,
  common mistakes, self-check questions with collapsed answers, and curated
  official docs, articles and videos. It is written into the project
  (`teach.syllabus_dir`, default `docs/syllabus/`) so it can be committed and
  published to GitHub Pages or any docs site. `/specclaw:teach syllabus`
  regenerates it on demand.
- **Resources are verified, never recalled.** Every article is fetched and every
  YouTube video is looked up through oEmbed in the same session, using the real
  title and channel. Without network access the chapter is written without its
  resource list, and the index says so.
- **It never breaks the one-artifact rule silently.** `teach.syllabus: ask`
  (default) asks once; `always` skips the question; `never` suppresses the offer.
  Build-time briefs still happen at the task and link to the chapter.
- `specclaw-teach syllabus [ask|always|never]` and `specclaw-teach syllabus-path`;
  `status` now reports `syllabus` and `syllabus_dir`. Setting a key that an older
  config lacks now adds it under `teach:` instead of failing.
- `references/syllabus.md` (recipe, structure, verification rules, checklist) and
  `tests/run-teach-tests.sh`, registered in CI.

## [Unreleased] — teaching mode (fork: Jayzilva/specclaw)

### Added
- **Teaching mode (`/specclaw:teach`).** Opt-in mode that makes the lifecycle
  explain while it builds, for onboarding, upskilling, and unfamiliar stacks.
  Off by default; when `teach.enabled` is false nothing changes anywhere.
  - `propose` names the technologies a change touches and asks the user's level
    per technology — (a) never used it / (b) theory only / (c) shipped with it /
    (d) deep — stored in `.specclaw/knowledge/learner-profile.md`.
  - `plan` surfaces design decisions as 2–4 scored options with pros, cons and
    costs, including one deliberately simpler than the recommendation. The user
    chooses; their reason is recorded verbatim in `design.md`.
  - `build` gates each wave that uses an unfamiliar technology, offering a
    3-minute concept brief, then builds without narration and returns exactly
    one verify command.
  - `verify` asks for a prediction before revealing numbers (`depth: full`).
  - `pr` runs a debrief: what was built, every decision with its alternatives
    and costs, and how the user would build it from scratch.
  - New `teaching.md` per change — the human-facing companion to `learnings.md`.
    Same change, two directions: one records what the machine learned, the
    other what the human learned.
  - **No cheatsheet library by design.** Concept briefs are generated from a
    recipe in `references/teaching-mode.md` and cached per project under
    `.specclaw/knowledge/briefs/`. A file per technology is a coverage promise
    no plugin can keep, and static files rot while model knowledge does not.
  - **Assessment is the default action.** A bare `/specclaw:teach` now runs a
    five-step flow — work out which technologies the change touches, ask for any
    level not self-reported, show the level map back, generate the learning plan,
    end with one next action. Previously it printed config and stopped, so a
    pre-populated profile meant the user was never actually assessed.
  - **Gates are inline in each phase's numbered flow, not appended.** An earlier
    iteration put the teaching section at the end of each skill, following the
    existing `loop.ci_gate` cross-reference pattern. That is correct for a
    cross-reference and wrong for behaviour that must interleave: in `build` the
    section landed after Step 3's wave loop, so a model working through the steps
    in order would spawn every coding agent and finish the build before reading
    the gate. Same class of bug in `verify` (prediction after the tests ran),
    `plan` (options after `design.md` was written) and `pr` (debrief after the PR
    was opened). Each skill now carries a short gate at the only position where it
    works — `build` Step 2.5 (after tasks are parsed, before agents spawn),
    `verify` Step 0.5, `plan` step 3d, `pr` step 1.5 — with the detail still at
    the end for reference.
  - **Stack table before any question.** The assessment now opens by showing every
    technology the change touches — libraries included, not just categories —
    with what each is for *in this project* and where it appears, then asks about
    every row. Previously it discovered technologies silently and only asked about
    gaps, so a learner never saw the surface area of the work and specific
    libraries (the Kafka client, the tracing propagation API, the trace UI) went
    unassessed while their parent category looked covered.
  - **Ends with one concrete opening move**, naming the first task, why it is
    first, which brief it opens with, and the exact words to reply — not a menu.
  - **Level provenance.** `specclaw-teach level <tech> <a|b|c|d> [self|assumed]`.
    `assumed` levels are listed by the new `assess` subcommand and must be
    re-asked before any phase trusts them — an inherited profile is not an
    assessment.
  - **Learning plan artifact** at `.specclaw/knowledge/learning-plan.md`, derived
    from the level map: separate Learn (briefs, each tied to the task that needs
    it), Explain (decisions that are the user's), PoC (only where watching a
    mechanism fail beats reading), and Implementation sections, plus predictions
    and an explicit not-learning-this-time list.
  - New `assess` and `plan-path` subcommands; `templates/knowledge/learning-plan.md`.
  - New `bin/specclaw-teach` (status / enable / disable / level / levels / log),
    `templates/teaching.md`, `templates/knowledge/learner-profile.md`,
    `references/teaching-mode.md`, and a `teach:` block in `templates/config.yaml`.

## [0.14.2] — 2026-08-25

### Added
- **`/specclaw:bf-quality` — a measured quality baseline, and an honest one.**
  Sizing a legacy rebuild has always rested on a reading of the code that nobody
  could reproduce. "The billing module is the scary one" is a real finding and it
  travels as hearsay: it cannot be re-measured after the rebuild, and it cannot
  be shown to a client who is being asked to fund the work.

  The new command writes `.specclaw/analysis/quality.json` — per-module rollups
  of cyclomatic complexity, function length, duplication and file length — plus a
  narrated `quality-report.md`. Four modes: the legacy report, `--target <path>`
  for the rebuilt tree, `--compare`, and `--compare --gate`.

- **Every verdict is computed in bash; the agent narrates and cannot re-derive.**
  Statuses, severities, per-module rollups and the gate result are all decided in
  the collector from thresholds that live only in `config.yaml`'s new `quality:`
  block. The narration agent is granted `Read` and `Write` and nothing else, so
  it has no way to run a metric tool or check a number against source even if its
  prompt failed to forbid it. A threshold that can be re-derived can be drifted,
  and these numbers end up in front of clients.

- **`NOT-MEASURED` is a result, not a gap.** No metric is ever estimated,
  extrapolated or filled in. When one cannot be computed it is recorded with a
  machine-readable reason — `language_unsupported`, `tool_missing`, or
  `parse_error` — and the report states the coverage **above** the findings
  rather than below them, because a reader who takes a rollup as complete without
  knowing a third of the tree was unmeasurable has been misled. Language support
  wins over a missing tool in that precedence: if no available tool parses the
  language, installing something would not help, and saying `tool_missing` would
  send someone off to fix the wrong thing.

- **`scc`, `lizard` and `jscpd` are all optional.** Each is probed per run and a
  missing one degrades only its own metrics. A run with none of them installed
  still succeeds, reports everything as `NOT-MEASURED`, and invents no hotspot.
  `jq` is the one hard dependency. Only documented machine-readable output is
  parsed — never scraped human output.

- **`QI-###` hotspots are permanent, and the registry is never archived.**
  `templates/quality-issues.md` joins `ST-###`/`IS-###` under `CONTRACT.md` (c)
  with one addition: the `quality.json` snapshot beside it *is* archived every
  run, which is exactly why the id space lives in a separate document. A hotspot
  that no longer exceeds its threshold is marked `resolved` and keeps its id and
  first-seen date forever — never deleted, because "this used to be a hotspot" is
  what distinguishes a module somebody cleaned up from one that was never bad.
  Identity is `metric|file|function|module`, never the measured value, so two
  reports months apart are comparable.

- **A one-sided comparison is `NOT-COMPARABLE`, never an improvement.** This is
  the flattering lie the compare mode exists to refuse. A legacy system in a
  language no tool parses for complexity reports `NOT-MEASURED`; the rebuild, in
  a well-supported language, reports `PASS`. Nothing has been shown to have
  improved — nobody knows what the legacy figure was — and the delta report says
  so in its own section, placed ahead of the wins.

- **Advisory by default, and provably optional.** The default mode exits 0 even
  when every module is `HIGH`. `--compare --gate` is the only enforcing path
  anywhere in the command, printing `QUALITY-GATE: PASS`/`FAIL (n regressions)`
  with a matching exit code, where a regression is a status *band* worsening at
  module level. No other command requires anything this one produces. The single
  interaction is `/specclaw:bf-rebuild-plan`, whose per-module coverage rollup
  gains a quality status and open-hotspot count when `quality.json` happens to
  exist — a guarded read whose every failure mode (no file, no `jq`, unreadable
  JSON, an unmeasured module) degrades to the same empty string, so the rendered
  backlog is byte-identical to a run predating the hook. `run-quality-tests.sh`
  asserts that by diffing two renders and requiring every differing line to be an
  annotation.

- **Module numbers describe the cited slice, and say so.** Nothing in
  `.specclaw/` maps a source file to a `MOD-###` — the module map maps modules to
  entities, rules, services and screens. So the join uses only the file paths each
  module cites in its own `**Evidence:**` bullets, an exact path citation beats a
  directory one, and a file two modules both cite is left under
  `MOD-UNASSIGNED` rather than allocated. A large unassigned bucket is the
  expected result on a map nobody has enriched, and it is reported loudly: the
  alternative — claiming every file under a cited file's directory — is inferring
  a boundary, which is the one thing `module-map.md` forbids.

- **Stack-blind.** No framework, product or project name appears in the
  collector. Language handling is an extension→tool-capability table, so adding a
  language is a row rather than a branch.


## [0.14.0] — 2026-08-19

### Added
- **`/specclaw:bf-clarify --options-pack` — the client decision paper the
  pipeline never had.** `clarifications.md` is written for engineers: seven type
  labels, `file:line` sources, an ID namespace. The people who actually get to
  choose the database, the hosting model or whether nine years of history moves
  were being handed that document, or a verbal summary of it, and **the decision
  was coming back attributed to "the client"** — which is to say, to nobody who
  could be asked about it later.

  It writes `.specclaw/analysis/options-pack.md`: every **undecided blocking**
  question, from any family, restated in plain language, with 2–3 candidate
  options, what each one means for *this* system, the trade-offs, and a
  recommendation. **It records nothing.** The choice goes back through the
  ordinary `clarifications.md` answer → `--resolve` path, attributed to a named
  human — which is also the remediation path for attribution generally.
- **Options are generated per run, never templated per stack.** There is no
  curated menu of databases, hosts or frameworks in any bash collector or
  template, and a hardcoded product name in one would be an architectural
  defect rather than a convenience. The agent generates candidates at run time
  from what this repo's own analysis documents show, cites each option's
  consequences by `file:line`, and labels a trade-off that is professional
  judgement rather than evidence `(judgment)` — so a client who cannot read the
  code can still tell a measurement from an opinion.
- **`/specclaw:bf-blueprint` — the target-side counterpart to
  `architecture.md`.** The pipeline was asymmetric. The legacy side had
  `architecture.md`, `domain-model.md` and `module-map.md`; the target side had
  its architecture scattered across `decisions.md`, ADRs, `bootstrap-plan.md`
  and the backlog, with **nothing that showed the shape of the thing being
  built** and nothing anyone could put in front of a client.

  It writes `.specclaw/analysis/target-architecture.md`: Mermaid C4 diagrams
  (one Context, one Container, one Component per `MOD-###`, grouped exactly as
  `rebuild-backlog.md` groups them), a **legacy→target mapping table in which
  every row cites the `SQ`/`CQ`/`UQ` decision that sanctions it**, and
  stack/persistence/hosting/auth sections where every claim carries its
  decision id.
- **It derives, it never decides.** A claim with no decision behind it renders
  `PROVISIONAL(<id>)` naming the open question rather than becoming a confident
  diagram box, and a module whose target shape is entirely undecided gets a
  single placeholder naming what blocks it — **never an invented design.** A
  speculative architecture is worse than an incomplete one: it reads as a plan,
  and somebody builds it.
- **Three bash gates that refuse the run rather than render something
  misleading**: a mapping row with no citation and no `PROVISIONAL`/
  `RETIRED-BY-DECISION` marker; a citation to an id that is not a real question
  (worse than an uncited row — it *looks* answered); and a missing section for
  an active module, or a section for one the map does not define.
- One test suite, registered in CI: `run-blueprint-tests.sh`.

### Changed
- **Decision status is computed in bash, in one place, for both new
  documents.** Whether a question is `DECIDED` / `UNDECIDED` /
  `NOT-APPLICABLE` is derived from `decisions.md`'s literal heading structure
  and `clarifications.md`'s own `## Not Applicable` section — the same
  discipline `sanction-check` and the bootstrap gate already use — and handed
  to the agents as a resolved verdict with the file that proves it. Neither
  agent re-derives it, and the blueprint's `**Blueprint status:** COMPLETE |
  PROVISIONAL (n unresolved blocking questions: …)` line is injected by bash,
  never asserted by an agent. A status an agent inferred by re-reading markdown
  is exactly the quietly-wrong claim this split prevents.
- **A question answered in `clarifications.md` but not yet `--resolve`d counts
  as decided.** Both new commands read the answer as well as the decision
  record, and report which file proved it. Reporting a question as undecided to
  the client who answered it that morning would make the pack lie.
- **Zero undecided blocking questions is a clean state, not an error.**
  `--options-pack` still writes the pack, saying nothing is pending and listing
  what was decided and by whom; `bf-blueprint` renders `COMPLETE` with no
  `PROVISIONAL` boxes. A project that has already answered everything gets a
  real document out of both commands, not a refusal.
- `target-architecture.md` joins the **Phase B copy set** in
  `docs/rebuild-workflow.md`, on the same terms as `module-map.md`: it travels
  for readability and nothing computes from it. `options-pack.md` deliberately
  does not travel — a stale copy in the rebuild repo would show questions as
  pending that have since been answered.
- `plugins/specclaw/CLAUDE.md` gains registry rows for `specclaw-bf-blueprint`
  and for `specclaw-bf-clarify`'s full subcommand set.

### Fixed
- Nothing in the new scan uses a tab as a field separator. A tab is an IFS
  *whitespace* character, so `IFS=$'\t' read` collapses runs of them and every
  field after the first empty one shifts left by a column — which an empty
  `Type` on a `## Not Applicable` entry produces every time. Both new scans use
  US (`0x1f`), which preserves empty fields.

## [0.13.0] — 2026-08-17

### Added
- **`/specclaw:bf-bootstrap` — the target-foundation stage the pipeline never
  had.** No command owned creating the rebuild's application skeleton. Every
  `bf-` analysis command is read-only and runs in the legacy repo;
  `bf-rebuild-plan` writes one document and calls no lifecycle command;
  `bf-replay` assumes the rebuild's real service and entity files already
  exist. The only writer of application source was `/specclaw:build`, scoped to
  one change — so **the first backlog item proposed inherited responsibility
  for inventing the skeleton, and inherited it invisibly**, because nothing in
  its spec, tasks or verify report said so.

  It reads the architecture the rebuild already decided (`decisions.md`'s
  SQ/CQ answers plus accepted ADRs in the new repo) and scaffolds for it: app
  shell, routing shell, API client, solution/project layout, DI, configuration,
  CORS, error-handling conventions, ORM and database connectivity, migrations
  infrastructure, test-project structure for both sides, theme plumbing, and
  one health-check endpoint to prove connectivity. Then it smoke-tests that,
  gates it, and records `.specclaw/bootstrap/bootstrap-manifest.json`.

  **Stack-agnostic and purely dynamic — no per-stack scaffold template ships in
  the plugin and none will.** The `bf-bootstrap-architect` agent generates the
  skeleton for whatever stack the decisions name, exactly as the baseline
  harness and the replay tests are generated.
- **A foundation-only gate, enforced rather than hoped.** The agent declares a
  census of everything it created — every file with a purpose, every route,
  every screen, every design-token group, every decision it consumed and from
  where — and bash checks that census against closed, stack-neutral
  vocabularies. A file declared `capability`, a route beyond the health check,
  or a `DR-###`/`BL-###`/`SCR-###` id anywhere in the scaffold each fail it.
  **It states its own limit**: a declared-census check plus id greps cannot
  prove the absence of capability logic, and a gate that overclaimed there
  would be worse than no gate.
- **A precondition gate on `/specclaw:propose`.** In a rebuild repo it now
  stops before creating anything: *"Target rebuild foundation has not been
  created. Run `/specclaw:bf-bootstrap` first."* Inert on any project with no
  `rebuild-backlog.md`, so nothing greenfield ever sees it, and it fails closed
  on a manifest it cannot parse. The one honest false positive — proposing an
  ordinary change inside the **legacy** repo, which also carries a backlog — is
  settled by a named human recording it once with
  `--not-applicable "<why>"`, never by inferring which repo we are in.
- **`SQ-014 — Target backend stack`** joins the standard question bank (bank
  version 1 → 2). `SQ-001` picks the platform and `SQ-006` the UI framework;
  between them **nothing asked what runs on the server**, and that gap is what
  left a real rebuild's backend decided-but-unrecorded.
- **`IS-###` item splits (`.specclaw/analysis/item-splits.md`)**, a persistent
  record of scope deliberately deferred, with its own three-state lifecycle
  (`ACTIVE → READY-TO-RESUME → COMPLETE`).
- Two test suites, both registered in CI: `run-bootstrap-gate-tests.sh` (59
  assertions) and `run-item-split-tests.sh` (89).

### Changed
- **`item-split` is no longer a stub strategy.** The other three *fake* a
  dependency — they produce an `ST-###`, can taint a verdict, and are retired
  when the real module lands. A split fakes nothing; it defers real scope. A
  stub asks *"was the thing under test real?"*; a split asks *"is this item even
  finished?"*, and answering that needs fields an `ST-###` entry never had (what
  was deferred, which rules each half covers, what unblocks it).
  `stub-append --strategy item-split` is now refused by name and points at
  `split-append`. **Existing entries are grandfathered, never rewritten** — ids
  are permanent — and are excluded from taint and from the retirement flow, with
  the manual step named once.
- **A split can no longer silently widen.** `split-append` refuses a rule
  partition that does not account for the item's acceptance basis exactly (a
  rule in neither half is scope belonging to nobody), and **refuses to defer the
  whole UI layer from a screen-bearing item** without a named human confirming
  that consequence. Screen-bearing is declared data — the item's own `SCR-###`
  citations or its rendered UI-fidelity line — never inferred from a title.
- **Re-proposing a split item resumes it.** `bypass-check` reports every
  non-`COMPLETE` split with what was built, its change/PR/replay evidence, what
  remains, and which blockers are now satisfied; a dependency an active split
  already deferred is classified `deferred-by-split` and is **not re-elicited**.
- **`--refresh` computes and writes `READY-TO-RESUME`.** Once every
  blocked-until item carries a declared `BUILT:` note, bash flips the entry —
  the `Status` line only, one direction, never back, with a `WARN` so it is
  never silent. This is the one place a rendering command writes into a
  registry, and it is deliberate: the transition is a pure function of declared
  data, so a stale `ACTIVE` would be indistinguishable from "nobody got round to
  it". `COMPLETE` stays a handoff — it needs a clean `--item` run to cite, and
  `split-update` refuses it straight from `ACTIVE`.
- **`--item` replay reports PARTIAL.** A run whose item carries an open split
  appends `(partial — split IS-###)` **after** the verdict token, names which of
  its fixtures cover built versus deferred scope, and states on the report's
  face that it is not that item's final acceptance;
  `run-metadata.json` records `not_final_acceptance`. **No verdict, divergence
  class or exit code changes** — `PASS` still parses as `PASS`, and a split never
  softens a `FAIL`. Deferred-scope fixtures are **reported, never excluded**:
  dropping one would change what the run fails on and hide a real regression
  behind a scope note, so a FAIL among them is explained and a PASS among them
  is flagged as worth investigating.
- `module-status.md` gains a **Partially built items** column and an
  **Item Splits By Module** section, kept distinct from the stub-tainted column:
  taint asks whether what a module was measured against was real, this asks
  whether its work is finished at all.
- The standard bank's version is now read from the bank file rather than
  hardcoded, so a question minted after the bank grew no longer records itself
  as coming from v1.

### Fixed
- **`⚠ PROVISIONAL` / `⚠ STUB-BACKED` markers doubled on every `--refresh` and
  never cleared.** A preserved item's prior marker was kept as part of its
  static body and a freshly computed one prepended on top, so the marker grew by
  one per refresh and stale copies survived after the underlying condition went
  away. Both documented claims — "recomputed fresh from nothing every run, never
  persisted from a prior refresh's own rendered marker" and "retiring a stub
  clears every marker automatically" — were false in practice for exactly the
  items a refresh does not re-draft. Reproduced, fixed, and now covered by
  tests.
- **A preserved section's own template comment duplicated once per
  `--refresh`.** The Coverage Check comment sits between its heading and its
  placeholder, so reading the section back picked it up as content and
  re-rendered it into a template that already contained it — four renders
  produced four stacked copies, growing the document without bound.
- **`item-split` registry entries tainted fixtures.** `resolve` and `render`
  filtered on `Status` alone and never on `Strategy`, so an `item-split` entry
  marked its items `⚠ STUB-BACKED` and stamped their fixtures `stub_refs` —
  contradicting three documents that each stated item-split taints nothing.

### Upgrade notes
- Existing brownfield projects will find **`SQ-014` unanswered** and
  `/specclaw:bf-bootstrap` will stop naming it. That is correct rather than a
  regression: the backend stack *was* decided somewhere, and this records it.
  Re-run `/specclaw:bf-clarify` (then `--resolve`) and re-copy `decisions.md`,
  or answer it directly in the rebuild repo.
- Projects with an existing `ST-###` entry whose `Strategy` is `item-split`
  will see those items **stop reporting as stub-tainted**, and the entry move
  out of the Stub Retirement flow into its own line. Nothing is migrated
  automatically; `split-append` records a real split if resume tracking is
  wanted.
- No baseline needs re-recording, and no manifest schema changed.

## [0.12.0] — 2026-08-13

### Fixed
- **`/specclaw:bf-replay` selected no fixtures at all on any correctly-run
  project.** `resolve` joined fixtures to backlog items solely through the
  manifest's `verifies_backlog_item`. The pipeline's own order runs
  `/specclaw:bf-baseline` (A4) *before* `/specclaw:bf-rebuild-plan` (A5), so on
  a first-recorded manifest that field necessarily holds the designer's
  documented `not yet backlog-linked` placeholder on every entry — which means
  change-scoped replay failed with `No fixtures matched selection` on every
  project that followed the documented sequence. A resolve design defect, not
  bad project data, and **no project needs its baseline re-recorded to get the
  fix**.
- **`ST-###` stub taint had never fired.** The taint join, and
  `run-metadata.json`'s `bl_items_covered` / `stub_tainted_items`, read the same
  placeholder field and so resolved to nothing — leaving
  `/specclaw:bf-rebuild-plan module-status` with no per-item verdicts to read.
  Taint now joins on the derived attribution, so it fires where it always
  should have. **Expect a first run after upgrading to report taint that
  earlier runs silently omitted.**

### Changed
- **The authoritative fixture join is now the backlog item's own acceptance
  basis.** A `BL-0##` resolves to its fixtures through the `DR-###` ids its
  acceptance basis cites, matched against each manifest entry's
  `business_rules_pinned` (ANY-of, as the `module_ids` join already was). This
  is deliberately the same chain `/specclaw:bf-rebuild-plan` walks to compute
  each item's `**Verification:** VERIFIABLE — fixtures: …` line, which makes the
  two testably equal — the suite asserts `--item BL-020`'s selection against a
  backlog rendered by that other tool, so a disagreement between them cannot
  ship silently.
- **`verifies_backlog_item` is demoted to a cross-check and is never
  load-bearing for selection again.** Populated and disagreeing with the join →
  a `WARN` naming both sets and the fix, with selection unchanged (one of the
  two documents is stale and bash cannot know which). Holding the placeholder →
  ignored in silence, because there is no disagreement to report.
- **`/specclaw:bf-baseline --record` now fills `verifies_backlog_item` and
  `module_ids`** from `rebuild-backlog.md` and `module-map.md` when those
  documents exist at record time, retiring the placeholder on any re-record.
  Fill-in only: a value a scenario declares itself always stands verbatim, and
  nothing downstream may require the result.

### Added
- **`/specclaw:bf-replay --item BL-###`** — a fourth selection scope for
  accepting one backlog item's behaviour on its own, **with no change directory
  required**. Validates that the item exists and is not a `STRUCK` tombstone,
  reports the item id and its fixture count, writes its report to
  `.specclaw/replay/report-<run_id>-BL-###.md`, keeps its evidence in the
  corpus-wide pool, and records `bl_items_covered` as exactly that one id — a
  shared fixture never quietly enters a second item's verdict history. Verdict
  logic, exit codes, `PROVISIONAL` semantics and taint mechanics are identical
  to every other scope; only selection differs.
- **The empty-selection contract.** A valid, active item with genuinely zero
  fixtures mapped to it is a *clean result*: `resolve` exits 0 with
  `NO BASELINE DATA — 0 fixtures mapped to BL-###`, and the run renders
  `INCOMPLETE` with the existing exit code 2, stating the same message on the
  report's face. Never a precondition crash, never an invented fixture, and
  never a `PASS` — a malformed manifest keeps its loud failure, and the
  placeholder is neither of these.
- **`specclaw-bf-replay parse-target`** — the four scopes are mutually
  exclusive (a positional `<change-name>` combines with no flag; the flags
  combine with nothing), and deciding whether an invocation is legal is now a
  mechanical bash job rather than something the skill's prose has to remember.
  Retention qualifiers still combine with any scope.

## [0.11.0] — 2026-08-12

### Added
- **Module bypass — build a module before its dependencies exist, without
  making that invisible.** The module dependency graph stays the *recommended*
  order; a team can now depart from it deliberately, per unmet dependency, and
  everything built on top of the departure is marked until the real module
  lands. Working out of order was always possible by simply doing it — what
  was missing was any way for a later reader to tell a verdict earned against
  a real module from one earned against a placeholder.
- **`.specclaw/analysis/module-stubs.md`** — the `ST-###` bypass registry. One
  entry per bypass: which `BL-0##`/`MOD-###` it substitutes, the strategy
  (`stub-interface` | `mock-data` | `feature-flag` | `item-split`), what it
  concretely fakes (cited `file:line` in the rebuild, written at build time),
  which items consumed it, who chose it and when. One shared corpus,
  **append/update-in-place, never archived** — like `clarifications.md`.
  `ST-###` ids are permanent; retirement updates an entry, never deletes it.
- **`/specclaw:propose` gained dependency awareness** (it had none). When a
  proposed item depends on a *cross-module* item with no completion signal,
  propose stops and presents the four strategies with concrete sketches
  grounded in what the dependency actually is, plus "it is actually built" and
  "abort and follow the recommended order". **A bypass is always an explicit
  human choice** — never agent-decided, never a default; entries record a
  named chooser and a date. Same-module dependencies are refused rather than
  offered a strategy: stubbing one means stubbing part of the thing being
  built. Three new bash subcommands (`bypass-check`, `stub-append`,
  `stub-update`) own the mechanical half; agents never compute any of it.
- **Spec carry-through.** `spec.md` gains `## Bypassed Dependencies`, and on a
  bypassed change **every** acceptance criterion is labelled `[real]` or
  `[stub: ST-###]`. Two criteria are mandatory per stub: the dev/test-scoping
  assertion naming the repo's own isolation mechanism, and the
  registry-completion obligation.
- **Stub taint in `/specclaw:bf-replay`.** Any fixture verifying an item that
  consumed an `ACTIVE` stub is stamped `stub_refs`, carried through
  `compare.json` into the report (`(with active stubs: ST-###)` on the verdict
  line, a **Stubs In Effect** section, a per-row Stubs column) and into
  `run-metadata.json`. A three-state flow (`ACTIVE` → `RETIRING` → `RETIRED`)
  makes a clean re-replay able to honestly retire a stub.
- **`module-status.md`** gained a **Stub-tainted items** column (latest run per
  item wins), renders `PASS*` while it is non-zero, and lists per module the
  `ST-###` entries faking *that* module for others — so "who is waiting on the
  real MOD-005" is one lookup.
- **`/specclaw:bf-rebuild-plan`** gained a bash-computed **Stub Retirement**
  block naming, per stub, the consuming items and the exact replay commands,
  with each step attributed to human or Claude — and a per-item
  `⚠ STUB-BACKED` marker alongside `⚠ PROVISIONAL`.
- `run-stub-registry-tests.sh` (42 assertions), registered in CI.

### Unchanged by design
- **Verdict logic and exit codes.** Taint enters no rule of `CONTRACT.md`
  (j.3), adds no `field_class` or `divergence_class`, and has no exit code of
  its own. It marks a PASS as resting on something unreal; **it never softens
  a FAIL**, which is asserted directly in the new suite. Unlike `PROVISIONAL`,
  which participates in the verdict because an open question means nobody has
  decided what correct is, a stub leaves the comparison sound and qualifies
  only its standing.
- **No re-record.** `manifest.json` and its schema number are untouched.
- **Greenfield and non-brownfield projects see nothing.** No registry means no
  stubs, silently; `bypass-check` returns `applicable: false` and propose
  behaves exactly as before.
- Evidence immutability, the fixture contract, and dependency ordering as the
  default recommendation.

## [0.10.0] — 2026-08-11

### Added
- **Module hierarchy (`MOD-###`) across the brownfield pipeline.** A large
  legacy system can now be migrated and behaviourally accepted **one module at
  a time** instead of through a flat whole-project backlog and all-or-one-change
  replay scoping. The hierarchy is `MOD-### → BL-0## → DR-### → GM-###`:
  modules are migration/acceptance units, backlog items remain the build units.
  Modules are a **selection dimension** over the one shared corpus — one
  manifest, one backlog, one `fixtures/` directory; nothing is split per module.
- **`.specclaw/analysis/module-map.md`** — written by `/specclaw:bf-domain`
  (new rubric dimension). Per module: purpose, owned entities, **referenced-but-
  not-owned** entities with their owner, services/routes, screens, owned
  `DR-###` rules, dependencies, and evidence (`file:line` or a quoted analysis
  passage) for every grouping claim. Grouping is evidence-based, never derived
  from directory names. The map is agent-**proposed** and human-**confirmed**
  via its own `Status:` line; every downstream command runs regardless and
  states on its face when the grouping is unconfirmed. `MOD-###` ids are
  **reconciled** across regenerations (name match, then ≥50% owned-entity
  overlap), never renumbered; a retired module leaves a `WITHDRAWN` tombstone.
- **Ambiguous boundaries become questions, not assignments.** A contested
  entity/rule/screen, or a reconciliation tie, raises a typed pending question
  (trigger `T3`) naming both candidate modules, places the item provisionally
  with a `⚠ PROVISIONAL` marker, and is typed `DECISION`/`SCOPE` by
  `/specclaw:bf-clarify`. No new question type was added — the seven-type
  taxonomy is unchanged.
- **`/specclaw:bf-rebuild-plan`** requires the map, groups items under
  `## MOD-###` headings in the map's own dependency order (cycles reported, not
  silently ordered), gives every item a declared `**Module:**`, adds a
  bash-computed per-module coverage rollup, recommends the **next module to
  build** with its reasons stated, and accepts `--module MOD-###` to (re)plan
  one module while preserving every other module's items, coverage lines, and
  human-added status notes.
- **`/specclaw:bf-baseline`** — each scenario declares the `MOD-###` module(s)
  owning the rules it pins (a scenario spanning modules is tagged with **all**
  of them); `record` carries these into `manifest.json`'s new `module_ids` and
  hard-fails on a module tag with no map heading; `--module` designs or extends
  a harness for one module without disturbing another's scenarios or generated
  tests, via the new deterministic `merge-scenarios` step.
- **`/specclaw:bf-replay --module MOD-###`** — a third selection scope between
  a change and `--all`, resolved by a pure jq join on `module_ids` (ANY-of).
  The report gains a **module rollup**: per-module counts, each module's own
  verdict, and — always — how many of its fixtures are **shared** with which
  other modules. Partial views are marked `PARTIAL`. Selection only: verdict
  logic and exit codes are identical across all three scopes.
- **`.specclaw/analysis/module-status.md`** — a read-only per-module status view
  (items planned/total, scenarios captured/designed, latest module-scoped replay
  verdict, open questions), regenerated in full by every
  `/specclaw:bf-rebuild-plan` run and deliberately exempt from
  archive-then-replace.

### Changed
- **`manifest_schema` 2 → 3**, adding per-fixture `module_ids`. **This forces no
  re-record**: change-scoped and `--all` runs still read a schema-2 manifest
  unchanged. Only `--module`, which is a join on that field, requires 3, and it
  fails with its own message naming the fix.
- `CONTRACT.md` gains section **(l)** (module hierarchy, ownership direction,
  the cross-module honesty rule, selection-only guarantee); `MOD-NNN` joins the
  ID-permanence rule in (c), which now also documents tombstones and
  reconciliation.
- `/specclaw:bf-rebuild-plan`'s Coverage Check and Sequencing Rationale are now
  actually taken from the planner agent's draft. They were previously discarded,
  so both sections rendered a placeholder string on a first run and every later
  `--refresh` preserved that placeholder — the agent's coverage work never
  reached the file.

### Fixed
- **Every fixture read `SUPERSEDED` on every re-record on Windows/MSYS.** jq's
  Windows build emits CRLF, so the manifest's recorded `scenario_content_hash`
  never equalled the recomputed one — holding every replay at
  `PASS-PENDING-DECISIONS` permanently, for a reason nothing surfaced.
- `split_scenario_blocks` did not stop at the next `## ` heading, so the last
  scenario absorbed `## No Legacy Behaviour Exists` and `## Rule Coverage Check`
  into its own block — putting unrelated prose inside its content hash (editing
  the coverage check marked that fixture `SUPERSEDED`) and letting a `MOD-###`
  mentioned in the coverage check read back as that scenario's declared module.
- `scenario_block_title` used a `[—-]` bracket expression, which byte-splits the
  multi-byte em dash on a byte-oriented sed build and left stray bytes on the
  front of every title — silently defeating every `WITHDRAWN*` tombstone check.

## [0.5.5] — 2026-07-17

### Added
- **Social preview card.** `docs/assets/social-preview.png` — a 1280×640,
  <1MB GitHub-ready Open Graph card derived from the hero image, for upload
  via Settings → Social preview (better link cards on X / Slack / Discord).

## [0.5.4] — 2026-07-17

### Added
- **Search & AI-discoverability for the docs site.** Enabled the
  `jekyll-sitemap` plugin with canonical `url`/`baseurl` so a `sitemap.xml`
  is generated for the GitHub Pages site; added `docs/robots.txt` (allow-all
  + sitemap reference), `docs/llms.txt` (short llms.txt-convention index) and
  `docs/llms-full.txt` (expanded text for LLM ingestion), keyword-tuned
  `docs/index.md`, and `docs/INDEXING.md` — a maintainer checklist for the
  owner-only steps (enable Pages, set homepage, Google Search Console, social
  image) plus drafted awesome-list submission text. Docs-only; no plugin
  runtime code changed.

## [0.5.3] — 2026-07-17

### Added
- **Repo discoverability & community health.** README now leads with status
  badges (CI, release, license, Claude Code compat, stars, PRs-welcome), a
  30-second try-it line, and a demo placeholder for a propose→plan→build→pr
  recording. Added `.github/` community files: bug-report and feature-request
  issue templates (`config.yml` routes questions to Discussions), a pull-request
  template with the version-sync checklist, `SECURITY.md`, and
  `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).
- **CI.** New `.github/workflows/ci.yml` runs the parser regression suite (with
  `jq` installed), ShellCheck over `bin/`, and a JSON + plugin/marketplace
  version-sync check on every push and PR.

## [0.5.2] — 2026-07-16

### Added
- **Grounded context discovery.** New `specclaw-discover-context` script
  auto-discovers project documentation repo-wide (`git ls-files` with a
  `find` fallback) and injects a budget-capped digest into plan, build,
  and verify payloads. Ranking honors a root `llms.txt`/`llms-full.txt`
  index first, then canonical root docs, doc directories, nested
  READMEs, and other markdown. Changelogs, licenses, code-of-conduct
  files, `archive`/`deprecated`/`i18n` content, dependency directories,
  and `.specclaw/` itself are excluded by default. Configured via a new
  `context:` block (`discovery`, `max_lines`, `folders`, `pin`,
  `exclude`) with Context7-style precedence: exclude → folders →
  include; `pin` bypasses both. Every over-budget file is named in the
  digest footer — nothing is dropped silently. `context.discovery:
  false` restores the exact previous behavior.
- **Plan phase grounding.** `/specclaw:plan` now builds a structured
  codebase survey, reads the discovered-docs digest, applies promoted
  `.specclaw/knowledge/spec-guidelines.md` (previously written by
  `learn --promote` but never read), and records the docs it used in a
  "Grounding sources" section of `design.md`.
- **Discovery regression tests.** Case 6 in `run-parser-tests.sh` — 11
  jq-free assertions over a static fixture tree covering ranking,
  llms.txt priority, default exclusions, filter precedence, pattern
  forms, budget accounting, the off switch, and git-tree enumeration.
- **Smart base branch detection.** New `detect_base_branch()` (duplicated
  into `specclaw-build` and `specclaw-pr` per the self-contained-script
  convention) resolves the base as: `git.base_branch` config override →
  `origin/HEAD` (self-healing via `git remote set-head origin --auto`) →
  `gh repo view` default branch → `main`/`master` fallback. New config key
  `git.base_branch` (empty = auto).

### Changed
- **Evidence-grounded agent payloads (prompt hardening).** Sourced from
  Anthropic's and OpenAI's published prompt-engineering guides:
  - Verify agent and code-reviewer now use quote-first verdicts — extract
    the exact AC/code/test-output lines a judgment rests on before judging;
    findings without quotable evidence are dropped.
  - Build/fix payloads gain Working Rules: investigate before answering
    (never speculate about unopened code), general-purpose solutions only
    (tests verify correctness, they don't define it; report bad tests
    instead of working around them), temp-file cleanup.
  - Build payload reordered task-last: longform spec/design/code first,
    task + constraints at the end (measured long-context win); guardrails
    stay first for prompt-cache locality.
  - Constraints now carry motivations (scope limit ↔ parallel-task
    conflicts + design_gap auto-logging; tests ↔ verify gate evidence).
  - Few-shot `<example>` pairs in agent-prompts.md (good/bad reviewer
    finding, strong/weak acceptance criterion).
  - Loop fix agents carry reversibility rules: no force-push, no
    `git reset --hard`, no `--no-verify`, no destructive shortcuts to
    green a gate — halt and escalate instead.
  - spec-author gains research discipline: competing hypotheses,
    confidence tracking, self-critique before the final write.
  Karpathy guardrails section remains verbatim.
### Fixed
- **`specclaw-build setup` no longer branches from arbitrary HEAD.** New
  change branches start from `origin/<base>` (fetched first, offline-safe
  local fallback); creating a branch while off-base prints a divergence
  warning so stacking is deliberate. Resume behavior unchanged. Setup JSON
  gains a `base_branch` field.
- **`specclaw-build finalize` merges into the detected base** instead of
  guessing `main`-else-`master`.
- **`specclaw-pr` no longer hardcodes `--base main`** — the PR targets the
  detected base; the version-bump comparison now uses the same single
  source of truth.

## [0.5.1] — 2026-07-16

### Added
- **Plugin update check.** New `specclaw-check-update` script: `/specclaw:status`
  now surfaces a one-line hint when a newer plugin version is published
  (compared against the plugin repo's raw `marketplace.json`, repo derived
  from plugin.json's `repository` field). Network at most once per 24h
  (cache `.specclaw/.update-check`, gitignore-recommended), 5s timeout,
  fail-silent on every error path — a notifier must never break a command.
  Gate: `plugin.update_check` config key (default true; `false` = zero
  network calls). Offline test hook `--remote-version` covers the compare,
  gate, cache, and silence paths in the suite.
## [0.4.2] — 2026-05-24

### Fixed
- **`specclaw-detect-patterns` path doubling.** Script formed `patterns.md`
  and `changes/` paths as `$specclaw_dir/.specclaw/...` while every sibling
  bin script (and `/specclaw:build`) treats `$specclaw_dir` as already being
  `.specclaw`. Result: `scan` looked for `.specclaw/.specclaw/changes/<name>`
  (not found) and `ensure_patterns_file` created a stray
  `.specclaw/.specclaw/patterns.md` stub on every build. Fixed the four
  affected lines to use `$specclaw_dir/...` directly.

## [0.4.1] — 2026-05-21

### Added
- **Per-repo knowledge base.** Promoting a learning or pattern now
  writes to `.specclaw/knowledge/` in the target repo — never to the
  plugin. `spec_gap`/`design_gap` learnings go to `spec-guidelines.md`;
  `pattern`/`best_practice`/`agent_issue` learnings and pattern
  prevention rules go to `agent-hints.md`. Plugin stays versioned and
  generic; repos accumulate their own knowledge over time.
- **Build agent auto-receives repo knowledge.** `specclaw-build-context`
  injects `.specclaw/knowledge/agent-hints.md` into every coding-agent
  prompt as a "Repo Knowledge Base" section when the file exists.
- **Knowledge templates.** `templates/knowledge/agent-hints.md` and
  `templates/knowledge/spec-guidelines.md` seed new knowledge bases.

## [0.4.0] — 2026-05-20

### Added
- **Agent guardrails injected into every coding agent.** Vendored
  Andrej Karpathy's CLAUDE.md (four behavioral rules: Think Before
  Coding, Simplicity First, Surgical Changes, Goal-Driven Execution)
  as `plugins/specclaw/references/agent-guardrails.md` (MIT, upstream
  `2c60614`). `specclaw-build-context` now prepends the guardrails as
  the first section of every coding-agent prompt — always-on, no
  config flag. Goal: reduce diff bloat, scope deviations, and
  speculative abstractions in agent-produced code.
- **Skill docs cross-reference the guardrails.** `skills/build`
  surfaces the auto-injection under Key Principles; `skills/plan`
  applies rules 1 & 2 to task decomposition; `skills/verify` frames
  itself as rule 4's goal-check loop against `spec.md` ACs.

### Behavior
- Missing `references/agent-guardrails.md` at build time emits a
  stderr warning and continues — packaging bug, not a build-blocker.

## [0.3.3] — 2026-05-15

### Fixed
- **Critical:** `sed_i` helper in 5 scripts (`specclaw-auth-azdo`,
  `specclaw-auth-jira`, `specclaw-pr`, `specclaw-azdo-pr`,
  `specclaw-detect-patterns`) had a recursive bug on **Linux only** —
  the Linux branch called `sed_i` instead of `sed -i`, producing
  infinite recursion → stack overflow → segmentation fault. Symptom:
  `specclaw-auth-azdo` segfaulted on Linux immediately after the
  `✅ Token valid` line, before saving credentials. macOS users were
  unaffected because the Darwin branch was correct. Root cause:
  v0.2.5's Python patcher's `re.sub(r'\bsed -i "', 'sed_i "', txt)`
  also matched inside the helper body and replaced its own fallback
  call. Fixed by reverting the Linux branch to `sed -i "$expr" "$@"`.

## [0.3.2] — 2026-05-15

### Fixed
- `/specclaw:pr` and `/specclaw:pr-azdo` now auto-stage and commit the
  `.specclaw/changes/<change>/` directory (proposal, spec, design, tasks,
  status, verify-report, errors, learnings) before opening the PR.
  Previously these planning artifacts were never committed by
  `specclaw-build commit` (which only commits each task's declared files),
  so PRs landed without the spec/design/verify trail. Reviewers had to
  read the linked GitHub Issue to see the plan. Now the artifacts ship
  in the PR diff alongside the code. `.specclaw/.env` is already
  gitignored and is not touched.

## [0.3.1] — 2026-05-15

### Fixed
- `yaml_val` across all 9 scripts (`specclaw-build`, `specclaw-pr`,
  `specclaw-azdo-pr`, `specclaw-azdo-issue`, `specclaw-jira-issue`,
  `specclaw-gh-sync`, `specclaw-validate-change`, `specclaw-verify`,
  `specclaw-verify-context`) now strips inline `#` comments before
  stripping surrounding quotes. Previously, a config line like
  `branch_prefix: "specclaw/"   # Prefix for feature branches` would
  parse to `specclaw/"   # Prefix for feature branches` instead of
  `specclaw/`, causing `specclaw-build setup` to construct malformed
  branch names. Caught when another Claude session ran `specclaw build`
  against a freshly-init'd config.

## [0.3.0] — 2026-05-15

### Added
- **Azure Boards integration** for proposal tracking — symmetric to the existing
  GitHub Issues and Jira integrations. Opt-in via `azdo.boards.sync: true` in
  `config.yaml`.
- New `specclaw-azdo-issue` script with subcommands `create`, `update`,
  `comment`, `close`, `link-pr`. Targets the ADO REST Work Items API.
  Reuses credentials from `/specclaw:auth-azdo`.
- New `/specclaw:azdo-issue` skill (model-invokable).
- Lifecycle hooks: `/specclaw:propose` creates the Work Item, `/specclaw:plan`
  updates description with the task checklist, `/specclaw:build` comments on
  task failures and wave-ends, `/specclaw:verify` comments with the verdict,
  `/specclaw:archive` posts a closing comment and adds a
  `closed-by-specclaw` tag.
- `/specclaw:pr-azdo` now **auto-links** the created PR to the Work Item via
  the ADO REST relations API (`ArtifactLink` of type `Pull Request`) so the
  PR shows up under the Work Item's "Development" panel. Failure is
  non-fatal — the PR is independently created.
- New config keys under `azdo.boards`: `sync` (default `false`),
  `work_item_type` (default `Feature`), `tag` (default `specclaw`).

### Notes
- specclaw does **not** auto-transition Work Item state — humans drive ADO
  state. State machines differ across process templates (Agile / Scrum /
  Basic / custom), so any auto-transition logic would be wrong somewhere.
  specclaw writes description, comments, and tags only.
- Default behavior is unchanged. Users who don't set `azdo.boards.sync: true`
  see no difference from v0.2.5.

## [0.2.5] — 2026-05-15

### Fixed
- Cross-platform `sed -i` portability. GNU sed accepts `sed -i "expr" file`
  but BSD sed (macOS) treats the expression as the backup-extension argument
  and the file path as the script — leading to errors like
  `sed: 1: ".../config.yaml": command c expects \ followed by text`.
  Added a `sed_i` helper to all 6 scripts that use in-place edits
  (`specclaw-auth-azdo`, `specclaw-auth-jira`, `specclaw-pr`,
  `specclaw-azdo-pr`, `specclaw-update-task-status`, `specclaw-detect-patterns`)
  which uses `sed -i ''` on Darwin and `sed -i` elsewhere.
- `specclaw-update-task-status --help` no longer errors on BSD sed
  (`extra characters at the end of p command`). Added a missing
  semicolon to the brace-group sed script.

## [0.2.4] — 2026-05-15

### Fixed
- `specclaw-auth-azdo` / `specclaw-auth-jira` no-tty error now prints a
  copy-paste-ready command with the script's **absolute path** and the
  resolved absolute path to `.specclaw/`. Previously the message said
  `cd <your-project>; specclaw-auth-azdo .specclaw`, which didn't work
  because the plugin lives in Claude Code's cache (not on the user's PATH)
  and the angle brackets were getting HTML-escaped by Claude Code's UI.

## [0.2.3] — 2026-05-15

### Fixed
- `specclaw-auth-azdo` and `specclaw-auth-jira` no longer crash with
  `/dev/tty: Device not configured` when an agent (like Claude Code)
  invokes them. They now detect missing `/dev/tty` upfront and exit with
  clear instructions telling the user to run the command directly from
  their own terminal (so they can paste their PAT / API token securely
  without going through an agent).
- The `auth-azdo` and `auth-jira` skill bodies now explicitly tell Claude
  to delegate the run to the user rather than invoking it.

## [0.2.2] — 2026-05-15

### Changed
- Tightened `/specclaw:propose` skill description to `INVOKE IMMEDIATELY` —
  Claude now fires the skill on the first turn when the user mentions a
  proposal/feature idea/change request, instead of gathering details
  conversationally first. The skill itself asks once for missing details.

## [0.2.1] — 2026-05-15

### Added
- `specclaw-ensure-init` helper script that idempotently creates `.specclaw/`
  if missing, using the current directory's basename as the project name.
- Every non-init skill now runs `specclaw-ensure-init` as Step 0, so any
  specclaw command (e.g. `/specclaw:propose`) works in a fresh project
  without requiring `/specclaw:init` first.

## [0.2.0] — 2026-05-15

### Changed
- Enabled model-invocation on 13 of 15 skills (everything except `auth-azdo`
  and `auth-jira`). Claude now routes conversationally — saying "i have a
  proposal" auto-fires `/specclaw:propose`. The two auth skills remain
  explicit-only because they handle credentials.

## [0.1.0] — 2026-05-15

First release as a Claude Code plugin.

### Added
- **Marketplace `chan4lk`** at `.claude-plugin/marketplace.json` — repo doubles as
  the chan4lk plugin marketplace. Future plugins by the same owner will be added
  under `plugins/<name>/` and registered in the same marketplace.
- **Plugin manifest** at `plugins/specclaw/.claude-plugin/plugin.json` — name
  `specclaw`, version `0.1.0`, MIT licensed.
- **Per-verb skills** under `plugins/specclaw/skills/<verb>/SKILL.md` — one skill
  per lifecycle verb (`init`, `propose`, `plan`, `build`, `learn`, `patterns`,
  `verify`, `pr`, `pr-azdo`, `auth-azdo`, `auth-jira`, `issue`, `status`,
  `archive`, `auto`). All skills use `disable-model-invocation: true` so they only
  fire on explicit slash-command invocation.
- **Executables in `bin/`** — every lifecycle script lives at
  `plugins/specclaw/bin/specclaw-<name>` and is on `$PATH` while the plugin is
  enabled. No more `bash skill/scripts/...` invocations.

### Changed
- All scripts resolve plugin-internal resources via `$CLAUDE_PLUGIN_ROOT` with a
  `BASH_SOURCE`-derived fallback for `--plugin-dir` dev mode. Scripts operate on
  the host repo's current working directory for `.specclaw/` state.

### Removed
- Top-level `skill/` directory. The previous layout
  (`skill/SKILL.md` + `skill/scripts/*.sh` + `skill/templates/`) is gone.

### Installation
```
/plugin marketplace add chan4lk/specclaw
/plugin install specclaw@chan4lk
```

Requires Claude Code v2.1 or later.
