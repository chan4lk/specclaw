# Clarify Standard Question Bank

**Bank version:** 3

<!--
  This is reference data for /specclaw:bf-clarify's bank layer, read directly
  by specclaw-bf-clarify (bash owns Type/Blocking/Options/Proposed default —
  see below) and by the bf-clarify-extractor agent's Mode: bank (applicability
  + pre-answered detection + contextualized wording).

  Every entry carries a permanent SQ-NNN ID, assigned once, in this file,
  at plugin-authoring time — NOT per-project. SQ-001 means "target
  platform" in every repo that ever runs /specclaw:bf-clarify; that
  consistency is the entire point of a separate ID space from CQ-NNN
  (which is allocated per-repo, in extraction order, and would drift the
  moment this bank grows). New entries take the next free SQ number.
  Retired entries leave a tombstone in place — never renumbered, never
  deleted — e.g.:

  ## SQ-005 — withdrawn 2026-09-01, superseded by SQ-013

  so a project whose clarifications.md already rendered SQ-005 keeps a
  stable citation even after a future plugin version retires it.

  Per-entry block format — every entry follows this exact structure:

  ## SQ-NNN — <short title>

  - **Type:** DECISION | DATA | SCOPE | DEFECT | MECHANICAL | TARGET-GAP | CONFLICT
  - **Blocking:** yes | no
  - **Question:** <generic wording — the agent contextualizes this with
    repo-specific facts when drafting the actual clarifications.md block;
    this is the fallback, not the goal>
  - **Options:**
    1. <option>
    2. <option>
  - **Proposed default:** <an option number, "adopt as-is", or "unknown —
    no legacy-code signal determines this; ask explicitly" for questions
    with no sensible universal default>
  - **Applicability:** <the condition the agent evaluates against the
    analysis docs to decide whether this question fires for a given repo,
    and what "not applicable" looks like>

  Type/Blocking/Options/Proposed default are bash-owned and identical
  across every project — specclaw-bf-clarify splices them into the rendered
  clarifications.md block directly from this file; the agent never
  authors or overrides them. The agent's job per new SQ is narrower:
  judge Applicability, draft a contextualized Finding/Why-it-matters, and
  check for a pre-existing answer (an *accepted* ADR or a decisions.md
  entry — a "proposed" ADR with an undecided placeholder decision counts
  as related context, not a pre-answer).
-->

## SQ-001 — Target platform

- **Type:** DECISION
- **Blocking:** yes
- **Question:** Target platform for the rebuild: web app, desktop, mobile, or hybrid?
- **Options:**
  1. Web application
  2. Desktop application
  3. Mobile application
  4. Hybrid / cross-platform
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Always applicable — every rebuild needs a target platform decided, regardless of what the legacy app's own platform was.

## SQ-002 — Database engine and hosting

- **Type:** DECISION
- **Blocking:** yes
- **Question:** Database engine and hosting for the rebuild — keep the legacy engine, or migrate to a different one (e.g. SQLite → SQL Server/Postgres)?
- **Options:**
  1. Keep the legacy database engine as-is.
  2. Migrate to a different engine sized for the target hosting model.
  3. Adopt a different persistence strategy entirely (state explicitly).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable whenever the legacy app persists data via a database, file store, or ORM of any kind — inapplicable only for a genuinely stateless tool with no persistence layer at all.

## SQ-003 — Hosting/deployment model

- **Type:** DECISION
- **Blocking:** yes
- **Question:** Hosting/deployment model for the rebuild (self-hosted, cloud, on-prem; single-tenant vs multi-tenant)?
- **Options:**
  1. Self-hosted / on-prem, single-tenant.
  2. Cloud-hosted, single-tenant.
  3. Cloud-hosted, multi-tenant.
  4. Other (state explicitly).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Always applicable — every rebuild needs a hosting model decided.

## SQ-004 — Authentication/authorization approach

- **Type:** TARGET-GAP
- **Blocking:** yes
- **Question:** Authentication/authorization approach — does the legacy app's (possibly absent) auth carry over, or does the target platform require real identity?
- **Options:**
  1. Preserve the legacy app's auth model as-is (including "none," if that's what it has).
  2. Add real authentication/authorization, sized to the target platform.
  3. Defer — ship without auth initially, add later (state the risk explicitly).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Always applicable — even when the legacy app has no authentication at all, that absence is itself the finding this question surfaces, not a reason to skip it.

## SQ-005 — Existing production data

- **Type:** SCOPE
- **Blocking:** yes
- **Question:** Existing production data: migrate it, start fresh, or partially import? If migrating, from how many installations?
- **Options:**
  1. Migrate all existing production data.
  2. Start fresh with no data migration.
  3. Partially import (state which subset explicitly).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable whenever the legacy app has any real persisted user/business data — inapplicable only if the analysis found the app has no meaningful persisted state to carry forward (e.g. a pure calculator/utility).

## SQ-006 — UI framework / component library

- **Type:** DECISION
- **Blocking:** no
- **Question:** UI framework / component library for the chosen platform?
- **Options:**
  1. Adopt a specific named framework/library (state which).
  2. Use the target platform's default/built-in components only.
  3. Undecided — defer to an implementation-time ADR.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable whenever the rebuild has any UI layer at all — inapplicable only for a pure backend/API/library rebuild with no UI of its own.

## SQ-007 — Concurrent multi-user support

- **Type:** SCOPE
- **Blocking:** no
- **Question:** Concurrent multi-user support — legacy desktop apps are often single-user; is the rebuild multi-user, and what does that change?
- **Options:**
  1. Single-user, matching legacy behaviour exactly.
  2. Multi-user with per-user data scoping.
  3. Multi-user, shared data, no per-user scoping.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable whenever the legacy app is single-user (the common case for legacy desktop software) and the target platform (web/server) makes multi-user a live question — inapplicable if the legacy app is already explicitly multi-user server software.

## SQ-008 — Browser/device/OS support matrix

- **Type:** DECISION
- **Blocking:** no
- **Question:** Browser/device/OS support matrix and accessibility bar?
- **Options:**
  1. Modern evergreen browsers only, no legacy support, standard accessibility (WCAG AA).
  2. Broader browser/device matrix (state explicitly).
  3. Not yet decided — defer to an implementation-time ADR.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable only once the target platform (SQ-001) is web, mobile, or hybrid — inapplicable for a desktop-only rebuild, where this question doesn't arise.

## SQ-009 — Reporting/printing/export behaviours

- **Type:** SCOPE
- **Blocking:** no
- **Question:** Reporting/printing/export behaviours of the legacy app — reproduce, replace, or drop?
- **Options:**
  1. Reproduce the legacy behaviour exactly.
  2. Replace with a modern equivalent (state what).
  3. Drop entirely (state why it's safe to drop).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable only if the analysis documents found an actual reporting/printing/export capability in the legacy app — inapplicable, with the reason stated, if no such capability was found anywhere in the analysis.

## SQ-010 — Non-functional targets

- **Type:** DECISION
- **Blocking:** no
- **Question:** Non-functional targets: expected data volume, user count, performance envelope (informs paging, caching, indexing choices the legacy app never needed)?
- **Options:**
  1. Small scale, no special performance work needed (state the rough numbers).
  2. Meaningful scale — paging/caching/indexing must be designed in from the start.
  3. Not yet known — defer to a later capacity-planning pass.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Always applicable — every rebuild benefits from an explicit scale target, even a small or "unknown yet" one.

## SQ-011 — Operational requirements

- **Type:** SCOPE
- **Blocking:** no
- **Question:** Operational requirements the legacy app lacked: backups, logging/monitoring, update/deployment cadence?
- **Options:**
  1. Add standard backups/logging/monitoring/CI-CD from day one.
  2. Defer operational tooling to a later phase (state the risk explicitly).
  3. Not applicable — the target hosting environment already provides this (state which).
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly.
- **Applicability:** Applicable whenever the analysis found no backup, logging/monitoring, or deployment tooling in the legacy app (the common case for legacy desktop software) — inapplicable if the analysis documents an existing operational story that already covers this.

## SQ-012 — Fidelity default

- **Type:** DECISION
- **Blocking:** no
- **Question:** Fidelity default: where legacy behaviour and "obviously better" conflict and no specific CQ exists, which way does the team lean?
- **Options:**
  1. Default to faithful reproduction of legacy behaviour unless a specific CQ says otherwise.
  2. Default to the "obviously better" behaviour unless a specific CQ says otherwise.
  3. No blanket default — decide case by case as each CQ/DEFECT question arises.
- **Proposed default:** 1 (adopt as-is by default — the safer default for a fidelity-focused rebuild; a specific DEFECT/CQ can always override it for one behaviour at a time).
- **Applicability:** Always applicable — this is a general policy default, useful regardless of what the extraction sweep did or didn't find.

## SQ-013 — UI fidelity policy

- **Type:** DECISION
- **Blocking:** yes — every backlog item that renders a screen
- **Question:** UI fidelity policy for this rebuild — how closely must the rebuilt interface reproduce the legacy one?
- **Options:**
  1. FAITHFUL — reproduce the legacy layout structure and colour theme exactly (within the target platform's own rendering norms).
  2. THEME-ONLY — keep the colour palette / branding tokens; layout is reinterpreted for the target platform.
  3. REINTERPRET — new design; the legacy UI is reference material only.
- **Proposed default:** 3 (REINTERPRET — the least-work interpretation, and precisely why it must never be assumed silently: answer this one explicitly rather than letting a rebuild quietly discard a UI the users know).
- **Applicability:** Applicable whenever the rebuild has any UI layer at all — inapplicable only for a pure backend/API/library rebuild with no UI of its own (the same condition as SQ-006). This is a different question from SQ-006, which picks the *framework*; this one sets how much of the legacy *appearance* the rebuild is held to. Answering FAITHFUL or THEME-ONLY activates the optional UI-fidelity workstream (`/specclaw:bf-ui`, and the SCR/TK grounding `/specclaw:bf-rebuild-plan` then requires); answering REINTERPRET costs nothing further anywhere in the pipeline. Either way the answer is verified by a named human signing a checklist, never by fixture replay — UI stays excluded from the golden-master seam taxonomy.

## SQ-014 — Target backend stack

- **Type:** DECISION
- **Blocking:** yes
- **Question:** Server-side language, framework and data-access approach for the rebuild?
- **Options:**
  1. Adopt a specific named language + framework (state which, including the data-access/ORM approach).
  2. No server-side component — the rebuild is a pure client, static site, or library.
  3. Undecided — defer to an implementation-time ADR.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly. The legacy app's own stack is *not* evidence here: replacing it is usually the point of the rebuild.
- **Applicability:** Applicable to every rebuild with any server-side component, which is nearly all of them. Answer option 2 (or mark this question Not applicable) for a genuinely client-only rebuild — that is a real answer and `/specclaw:bf-bootstrap` accepts it. This is deliberately separate from SQ-001 (which picks the *platform*: web, desktop, mobile) and SQ-006 (which picks the *UI framework*): between them those two never determine what runs on the server, and that gap is what left the target backend undecided-but-assumed on a real rebuild. `/specclaw:bf-bootstrap` requires this one resolved before it will scaffold anything, and stops naming this id rather than inferring a stack from the legacy app or from convention.

## SQ-015 — Target frontend language

- **Type:** DECISION
- **Blocking:** no
- **Question:** Which language is the rebuilt frontend written in?
- **Options:**
  1. Adopt a specific named language (state which).
  2. The same language already named in the SQ-006 answer — restate it here explicitly.
  3. Undecided — defer to an implementation-time ADR.
- **Proposed default:** unknown — no legacy-code signal determines this; ask explicitly. Neither the legacy app's language nor the chosen framework's usual language is evidence: the first is what the rebuild is replacing, and the second is a convention nobody in this project decided.
- **Applicability:** Applicable only when SQ-013 is decided REINTERPRET. Under FAITHFUL, THEME-ONLY, an undecided SQ-013, or a rebuild with no UI layer, mark this Not applicable — the rest of the pipeline never reads it and asking would be noise. Under REINTERPRET it is required, because `/specclaw:bf-prototype` builds a throwaway prototype in the decided stack for a named client stakeholder to approve screen by screen, and it refuses to run until the framework *and* the language are each decided with a citation. This is deliberately separate from SQ-006, which picks the *framework* only: a framework name decides a framework and nothing else, and a rebuild that answered SQ-006 alone has silently inherited whichever language its framework's convention implies — which is exactly the assumption this entry exists to stop. If SQ-006's own answer already names both (written as `<framework> (<language>)`, the language a single bare word), that one answer decides both and this question is answered as option 2 or marked Not applicable. `/specclaw:bf-prototype` stops naming this id rather than defaulting the language to anything.
