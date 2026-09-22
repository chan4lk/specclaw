# Model Invocation Map — bf-* Spawn Site Audit

This document classifies every `Agent` tool spawn site in the nine brownfield (`bf-*`)
skills as **`narration`** (the artifact the agent produces is already final before it
runs — a deterministic renderer could replace it) or **`judgement`** (the agent decides
something bash cannot derive, and is never skippable). It exists so a later change can
extend `bf.narration`-style opt-outs (change `039-model-invocation-opt-out` ships the
switch for exactly one row, `bf-quality`) without guessing at which spawns are actually
safe to skip. Every row cites the exact line that justifies its call, and every
`narration` row states the deterministic fallback that would replace the spawn.


> **On the line citations.** The `SKILL.md:<line>` in each row is a convenience anchor, not the
> evidence. The evidence is the **quoted sentence** beside it, which survives any edit that moves a
> line. The numbers went stale once already — inside the very change that created this table, when
> its sibling task inserted two lines at each of fifteen sites — so `run-narration-gate-tests.sh`
> (Group H) now asserts that every cited line actually holds a `subagent_type`, and fails if one
> drifts again.


## How to read a row

- **Site** — the skill file and the exact `SKILL.md:line` where the `Agent` tool is
  invoked (from `grep -rn 'subagent_type' skills/bf-*/SKILL.md`).
- **Agent / mode** — the `subagent_type` and, for a multi-mode agent
  (`bf-clarify-extractor` has five modes; `bf-baseline-designer`, `bf-ui-analyst`, and
  `bf-replay` each have two different agents/modes across their sites), which mode this
  particular site runs.
- **Classification** — `narration` or `judgement`, per the model below.
- **Evidence** — a verbatim quote from the cited `SKILL.md` line or the agent's own
  charter in `plugins/specclaw/agents/*.md` that justifies the call. No row asserts a
  classification without a quote.
- **Deterministic fallback (narration only)** — what bash-produced artifact already
  contains the bytes a renderer would need to replace the spawn. Left blank for
  `judgement` rows, since by definition nothing already computed could stand in.

**The model for `narration`** is `bf-quality`: its skill tells the agent *"every status,
severity, rollup and verdict in the JSON is already final"*
(`skills/bf-quality/SKILL.md`), and three of its report's sections are
collector-rendered markdown the agent pastes **verbatim** between anchors
(`skills/bf-quality/SKILL.md`) — its collector already emits `report_blocks.*_md`
(`bin/specclaw-bf-quality-collect:2438-2440`). A site only earns `narration` when its
facts are computed and finalized *before* the agent is spawned, not merely when the
agent's output happens to be readable and evidence-grounded — every `bf-*` analysis
agent is evidence-grounded, and grounding is not the same thing as being already final.

**Decision rule.** Per the change's guardrails: classify `judgement` when unsure. A wrong
`narration` call produces a silently missing answer; a wrong `judgement` call costs only
one spawn that could have been skipped. Every ambiguous case below is called out as such
rather than resolved optimistically.

---

## The 19 sites

| # | Site | Agent / mode | Classification | Evidence | Deterministic fallback |
|---|------|---------------|-----------------|----------|--------------------------|
| 1 | `bf-analyze/SKILL.md:32` | `bf-codebase-analyst` | **judgement** | `agents/bf-codebase-analyst.md` (Evidence Discipline): *"Every claim must be anchored to a quote from a file you actually opened via your `Read` tool during this run — name the path and quote the relevant text… A claim you cannot anchor to a file you opened is not a finding: drop it rather than report a vague suspicion."* The collector hands the agent raw file/manifest facts, not a finished report — the agent must open files itself and form inferences. | — |
| 2 | `bf-architecture/SKILL.md:25` | `bf-architecture-analyst` | **judgement** | `agents/bf-architecture-analyst.md` (Evidence Discipline): *"Every diagram node, every diagram edge, and every prose claim must be anchored to either a collected fact… or a quote from a file you actually opened via your `Read` tool during this run… A claim you cannot anchor this way is not a finding: drop it rather than report a vague suspicion."* Container/component boundaries and the L4 Judgment Rule call require real interpretation of `dependency_graph` plus opened files — none of it is precomputed. | — |
| 3 | `bf-baseline/SKILL.md:38` | `bf-baseline-designer` (design mode) | **judgement** | `agents/bf-baseline-designer.md` (Identity): *"A confident wrong seam ranking, a fabricated scenario, or harness code that silently swallows an error is worse than an honestly flagged gap."* Task 1 requires the agent to *"Classify every candidate into exactly one of five classes, each with a real citation, and declare its `seam_layer`"* — a ranking and a determinism audit computed nowhere before the agent runs. | — |
| 4 | `bf-baseline/SKILL.md:78` | `bf-baseline-designer` (harness mode) | **judgement** | `agents/bf-baseline-designer.md` (frontmatter description): *"Also identifies the legacy repo's own stack, generates the runnable capture harness code for it under `.specclaw/baseline/harness/`, and authors the project's own semantic error vocabulary in `.specclaw/baseline/error-map.md`"* — this spawn writes real, runnable source code; there is no artifact to narrate because none exists until the agent writes it. | — |
| 5 | `bf-blueprint/SKILL.md:37` | `bf-blueprint-architect` | **judgement** (see note) | `agents/bf-blueprint-architect.md` (The one rule everything else follows from): *"A claim with no decision behind it renders `PROVISIONAL(<id>)`, naming the open question, and never becomes a confident box in a diagram."* The agent must draft prose, mapping-table rows, and Mermaid diagrams by reading and synthesizing `decisions.md`'s natural-language text — that synthesis is not precomputed. **Note:** the document's own `COMPLETE`/`PROVISIONAL` header verdict *is* precomputed — `skills/bf-blueprint/SKILL.md`: *"Decision status is computed here and only here. The agent is handed the verdict and never re-derives it…"* — making this the closest analog to `bf-quality` among the 18 non-pilot sites (see Summary). | — |
| 6 | `bf-bootstrap/SKILL.md:64` | `bf-bootstrap-architect` | **judgement** | `skills/bf-bootstrap/SKILL.md` itself: *"deliberately **not** `models.review`, which every sibling `bf-` agent uses. Those agents read documents and write findings; this one writes real application source, which is build work."* Build work is the definitional opposite of narrating an already-final artifact. | — |
| 7 | `bf-domain/SKILL.md:29` | `bf-domain-analyst` | **judgement** | `agents/bf-domain-analyst.md`: *"Whether an entry states a real business rule is entirely your judgment to make — see the Rubric, the **Candidate-Hint Rule**, and the Mechanical Recording Rule below."* The collector's `validation_routine_candidates[]` is explicitly documented as *"a **hint list only**, not asserted rules"* — the facts are not final until the agent judges them. | — |
| 8 | `bf-e2e/SKILL.md:26` | `bf-e2e-architect` | **judgement** | `skills/bf-e2e/SKILL.md` itself: *"this agent writes real, runnable test code, the same routing as build's coding agents, not the read-only analysis agents."* Same build-work reasoning as row 6 — nothing to narrate because the test code doesn't exist yet. | — |
| 9 | `bf-rebuild-plan/SKILL.md:29` | `bf-rebuild-planner` | **judgement** | `agents/bf-rebuild-planner.md`: *"That split exists because a living backlog's hard invariants — never renumber, never lose a human-added status note, never silently drop a struck or deferred item — are safer enforced deterministically than trusted to your judgment across repeated runs."* Gate/Verification per item are bash-recomputed at render time (`skills/bf-rebuild-plan/SKILL.md`), but the backlog items' own titles, descriptions, and dependency-aware sequencing are the agent's synthesis, not precomputed. | — |
| 10 | `bf-clarify/SKILL.md:32` | `bf-clarify-extractor` (ingest mode) | **judgement** | `agents/bf-clarify-extractor.md` (Mode: ingest, Task step 1): *"Use the entry's own `trigger` and content as your guide, not a mechanical trigger→type lookup — `T4` content is usually `DEFECT` and `T5` is usually `TARGET-GAP`, but read the actual finding before typing it."* Even though evidence fields are carried forward verbatim, the four-way `DECISION`/`DEFECT`/`SCOPE`/`TARGET-GAP` type judgment is explicitly *not* reducible to a lookup table. | — |
| 11 | `bf-clarify/SKILL.md:37` | `bf-clarify-extractor` (extract mode) | **judgement** | `agents/bf-clarify-extractor.md` (Mode: extract): the agent must run a two-pass sweep for extraction signals and assign each finding one of seven taxonomy types (DECISION/DATA/SCOPE/DEFECT/MECHANICAL/TARGET-GAP/CONFLICT) — *"`DEFECT` is the type most easily missed and most consequential… Actively hunt for it in every business rule you read; don't wait for it to jump out."* Nothing about which questions exist is known before this spawn runs. | — |
| 12 | `bf-clarify/SKILL.md:42` | `bf-clarify-extractor` (bank mode) | **judgement** (see note) | `agents/bf-clarify-extractor.md` (Mode: bank, Task step 1): *"Judge Applicability against that bank entry's own `Applicability` condition, using only what you actually read in the analysis documents this run… Never guess an applicability verdict from the question's topic alone."* **Note:** `Type`/`Blocking`/`Options`/`Proposed default` for every `SQ-NNN` are *not* the agent's to draft — *"specclaw-bf-clarify render splices those directly from the bank file into the final block, identical across every project"* — only Applicability and the pre-answered check are live judgment, and the pre-answered check (an ADR whose `Status:` field is literally `accepted`) is close to a mechanical grep, making this the second-closest analog to `bf-quality` (see Summary). | — |
| 13 | `bf-clarify/SKILL.md:64` | `bf-clarify-extractor` (resolve mode) | **judgement** | `agents/bf-clarify-extractor.md` (Mode: resolve, Task): *"Bias toward 'yes' for `DECISION`, `DEFECT`, and `TARGET-GAP` types with broad or architectural impact; bias toward 'no' for `MECHANICAL` calls and narrow `SCOPE` calls — but judge each on its actual content, not just its type label."* The promote/don't-promote call plus a suggested ADR title cannot be derived from the decision text mechanically. | — |
| 14 | `bf-clarify/SKILL.md:96` | `bf-clarify-extractor` (options-pack mode) | **judgement** | `agents/bf-clarify-extractor.md` (Mode: options-pack): *"You generate 2–3 candidate options per question, at run time, from what this repo's own analysis documents actually show… Not one — a single option is a decision already made, presented as a question."* Options and their trade-offs (each explicitly labelled `(judgment)` where they are judgment, per that mode's own Evidence Discipline section) are invented fresh every run — nothing about them exists beforehand. | — |
| 15 | `bf-replay/SKILL.md:145` | `bf-replay-mapper` | **judgement** | `agents/bf-replay-mapper.md` (Identity): *"You decide whether a captured legacy fixture *can* be replayed against the new app's current code, and if so, you write the test that replays it… A confident wrong REPLAYABLE classification… or a fabricated NOT REPLAYABLE excuse… is worse than an honestly flagged uncertainty."* The agent both classifies REPLAYABLE/NOT REPLAYABLE and writes real generated test code — build work, same as rows 4/6/8. | — |
| 16 | `bf-replay/SKILL.md:201` | `bf-replay-auditor` | **judgement** | `agents/bf-replay-auditor.md` (Identity): *"Your only job is to look up whether a real, decided product decision already sanctions each behavioural divergence the mechanical comparison found — never to judge whether the new behaviour is *better*."* Finding and quoting a sanctioning `CQ`/`SQ`/`UQ` (or concluding none exists) requires reading `decisions.md`'s prose and judging whether it covers the *specific* diverging field — `specclaw-bf-replay sanction-check` only re-verifies the citation is real afterward, it does not perform the search itself. | — |
| 17 | `bf-quality/SKILL.md:90` | `bf-quality-analyst` | **narration** | `skills/bf-quality/SKILL.md`: *"Tell the agent explicitly that every status, severity, rollup and verdict in the JSON is already final."* `skills/bf-quality/SKILL.md`: *"Three of the report's sections are not narration at all. `report_blocks.scan_funnel_md`, `report_blocks.module_rollup_md` and `report_blocks.coverage_sentence_md` are markdown the collector rendered, and the agent pastes each one verbatim between the `<!-- quality-report:… -->` anchors."* | `specclaw-bf-quality-render` (this change) reads `quality.json` directly, copies the three `report_blocks.*_md` fields verbatim between the template's anchors, and replaces every narrated section with the fixed `_Not narrated — deterministic mode. Facts below are collector output._` marker. Checkable by the existing `… collect lint` byte-identity check (`bin/specclaw-bf-quality-collect:3286`). |
| 18 | `bf-ui/SKILL.md:36` | `bf-ui-analyst` (extract mode) | **judgement** | `agents/bf-ui-analyst.md` Step 1 header: *"Identify the view technology yourself, from the repo"* — the collector deliberately reports only a stack-agnostic extension histogram; `skills/bf-ui/SKILL.md`: *"it names no view framework, no markup/style/resource file type, and no toolchain… identifying which of those are views and what technology that implies is the agent's job, per run, by reading the repo."* Nothing about the screen inventory, tokens, or technology exists before this spawn. | — |
| 19 | `bf-ui/SKILL.md:80` | `bf-ui-analyst` (checklist mode) | **judgement** | `agents/bf-ui-analyst.md` (Mode: checklist): *"For each token in each supplied group, find where that value is (or should be) defined in the new repo — a theme file, a token/variable declaration, a stylesheet, a config — and record a `path:line` a reviewer can open… Identify the new repo's own stack and conventions yourself, by reading it."* This is a live investigation of the rebuild repo's current source, not a rendering of a precomputed fact — the location a token lives at is not known until the agent searches for it. | — |

---

## Summary

**Counts:** 19 spawn sites total — **1 `narration`** (row 17, `bf-quality`), **18
`judgement`**.

**This change (`039-model-invocation-opt-out`) wires `bf.narration`/`--no-model` for
exactly the one `narration` row.** No other site is reclassified or touched by L2 in
this change — every `judgement` row above stays a mandatory spawn.

**Priority order for a future `bf.narration` extension**, i.e. which `judgement` sites
most resemble the `bf-quality` pattern closely enough that restructuring their
collectors to pre-render markdown blocks (the way `bf-quality-collect` already does)
could plausibly turn them into legitimate `narration` rows later. This is a forward-
looking, non-binding assessment — none of these are reclassified here, and per the
decision rule above, a marginal case stays `judgement` until the evidence for
`narration` is as clean as row 17's:

1. **`bf-blueprint` (row 5).** The document's own `COMPLETE`/`PROVISIONAL` verdict is
   already bash-computed and handed to the agent as a fact it must never re-derive
   (`skills/bf-blueprint/SKILL.md`), and the agent's own charter frames its role as
   synthesist rather than architect. What currently blocks a `narration` classification
   is that the bulk of the document — mapping-table prose, Mermaid diagrams, stack
   sections — is still drafted fresh from `decisions.md`'s natural-language text each
   run, not pasted from a pre-rendered block. A collector upgrade that pre-renders the
   mapping table and diagram skeletons from `decisions.md` + `module-map.md` would close
   most of that gap.
2. **`bf-clarify` bank mode (row 12).** `Type`/`Blocking`/`Options`/`Proposed default`
   are already spliced deterministically from the bank file by `render`, never drafted
   by the agent. The remaining live judgment — Applicability, and the "is there an
   already-`accepted` ADR that answers this" pre-answered check — is close to a
   mechanical condition (grep an ADR's `Status:` field) that a smarter collector could
   plausibly precompute for a large fraction of bank questions.
3. **`bf-clarify` resolve mode (row 13).** The decision text itself is already
   mechanically transcribed into `decisions.md` by `resolve-render`, never by the agent.
   The only live judgment is a promote/don't-promote boolean plus a suggested ADR title
   — a narrower decision than most other judgement rows, though the skill is explicit
   that it must be judged "on its actual content, not just its type label," which is why
   it ranks behind row 12 rather than ahead of it.

Every other `judgement` row (1–4, 6–11, 14–19) either writes real source/test code, does
open-ended investigation of the actual repo (reading files, searching for signals,
locating tokens), or performs a classification/citation judgment the relevant agent
charter explicitly says is *not* reducible to a mechanical lookup — none of them have a
collector-precomputed artifact anywhere close to what `bf-quality`'s `report_blocks.*_md`
already provides.
