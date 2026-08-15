# Spec: Party mode — an adversarial panel that argues a proposal before it becomes a plan

**Change:** 032-party-mode
**Created:** 2026-08-15
**Status:** 🟡 Draft

## Overview

Party mode adds an adversarial review gate to `/specclaw:propose`. A panel of role-specialised
subagents critiques `proposal.md` from non-overlapping angles, rebuts each other, and produces
`party-report.md` with a deterministically-tallied verdict and a preserved record of dissent.

The panel is **sized to the proposal**: a `haiku` classifier reads the artifact and returns a depth
tier plus domain flags; `specclaw-party panel` turns that judgement into a concrete roster. A thin
proposal draws two seats; a deep one with a security dimension draws five, including one on `fable`.

Two invariants shape everything below, both inherited from existing specclaw practice:

1. **A model judges; a script decides.** The classifier picks a tier and the panelists write
   findings — but seat resolution and the verdict tally are bash arithmetic. This is the same split
   as `specclaw-loop` (controller owns gate evaluation) and `specclaw-parse-tasks --count` (one
   counter, no `grep` elsewhere).
2. **Party mode informs; the operator decides.** The gate never blocks `/specclaw:plan` by default
   and never edits the proposal's argument. It costs tokens and produces a report.

Secondary surface: the same panelists can be pointed at a `/specclaw:loop` halt, where the failure is
one of strategy rather than of diff.

## Requirements

### Functional Requirements

**FR1 — `specclaw-party` script.** A new `bin/specclaw-party` with subcommands:

| Subcommand | Behaviour |
|------------|-----------|
| `panel <specclaw_dir> <change> [--panel <tier>] [--json]` | Resolve the roster; write `changes/<change>/party/panel.json`; print a human summary (or JSON with `--json`) |
| `tally <specclaw_dir> <change>` | Read the round-2 findings file, apply the verdict rule, print the verdict |
| `report <specclaw_dir> <change>` | Assemble `party-report.md` from the findings and the tally |
| `-h` / `--help` | Usage |

**FR2 — Depth classification is a model call.** `panel` invokes the `party-classifier` subagent
(`model: haiku`) which reads `proposal.md` and returns JSON:

```json
{"tier": "thin|standard|deep",
 "domains": ["security"],
 "rationale": "one sentence",
 "signals": {"blast_radius": "...", "unresolved": "...", "irreversibility": "..."}}
```

The classifier's charter defines depth as: how many subsystems actually change, how much of the
design is still unresolved, how reversible the change is, and whether it touches trust boundaries,
data shape, or release machinery. Prose volume is explicitly **not** a depth signal.

**FR3 — Self-declared complexity escalates only.** The proposal's own `**Complexity:**` and
`**Risk:**` lines are written by the same model that wrote the proposal. The classifier charter must
treat them as a claim: a `high`/`large` declaration may raise the tier; a `low`/`small` declaration
is ignored and the judgement stands on substance.

**FR4 — Deterministic seat resolution.** Given a tier and domain flags, `panel` resolves seats in
bash, with no further model involvement:

| Tier | Seats |
|------|-------|
| `thin` | `party-po`, `party-architect` |
| `standard` | `party-po`, `party-architect`, `party-ba` |
| `deep` | `party-po`, `party-architect`, `party-ba`, `party-visionary` |
| any tier | `+ party-security` when `security ∈ domains` **or** tier is `deep` |

Then: union with `party.always`, clamp to `party.min_seats` (default 2) and `party.max_seats`
(default 6). Clamping drops seats from the tail of the tier order (Visionary first, PO/Architect
last) and records what it dropped.

**FR5 — Fail loud, never quiet.** If the classifier errors, exits non-zero, emits unparseable JSON,
or returns an unknown tier, `panel` uses tier `standard`, sets `"tier_source": "fallback"` in
`panel.json`, and prints a warning on stderr. It never falls back to `thin`.

**FR6 — The decision is auditable.** `panel.json` records: `schema_version`, `tier`, `tier_source`
(`classifier` | `fallback` | `override` | `fixed`), `rationale`, `domains`, `seats`, `dropped`
(from clamping), and the resolved `model` per seat.

**FR7 — Overrides bypass the classifier.** `party.panel_mode: fixed` uses `party.panel` verbatim;
`--panel <tier>` forces a tier. Both skip the classifier spawn entirely (no cost) and are recorded in
`tier_source`.

**FR8 — Five panelist agents, each with its own model.** New definitions under `agents/`, following
the `code-reviewer.md` shape (frontmatter `name` / `description` / `tools` / `model`; body with
identity, inputs, output contract):

| Agent | Mandate | Must not comment on | Model |
|-------|---------|---------------------|-------|
| `party-ba` | Problem fidelity — is the stated problem the real problem, is the evidence real | implementation choices, cost | `sonnet` |
| `party-po` | Value per token — cheapest thing that captures most of the value; the do-nothing option | architecture, security | `sonnet` |
| `party-architect` | Structural fit, duplication, blast radius across subsystems | product value, wording | `opus` |
| `party-security` | Trust boundaries, abuse, what happens when it misfires | scope creep, naming | `opus` |
| `party-visionary` | Does this compound, or make the next change harder | line-level detail | `fable` |

**FR9 — Evidence discipline.** Every finding quotes the exact line(s) of `proposal.md` it flags. A
finding that cannot be anchored to quoted text is dropped, not softened — the rule `code-reviewer`
already enforces (`agents/code-reviewer.md`, "Evidence Discipline").

**FR10 — Obligation to object.** Each panelist emits at least one finding **or** an explicit
`### [NOTE] — no objection under this lens` entry. Silence is not a permitted output; a panel that
agrees must say so in writing.

**FR11 — Two rounds.** Round 1: all seats spawn in parallel, each seeing only `proposal.md` and its
own charter — no panelist sees another's output. Round 2: each seat receives all round-1 findings and
must mark each of its own as `upheld` or `withdrawn: <reason>`, and may add rebuttals of others'
findings. `party.rounds: 1` skips round 2.

**FR12 — Deterministic tally.** `tally` computes the verdict from round-2 findings only:

| Condition | Verdict |
|-----------|---------|
| ≥1 upheld `BLOCK` | `CHANGES_REQUESTED` |
| ≥2 distinct roles with an upheld `WARN`, or ≥3 upheld `WARN` from one role | `APPROVED_WITH_NOTES` |
| otherwise | `APPROVED` |

Withdrawn findings never count toward a verdict. No model decides the verdict.

**FR13 — Report contract matches the existing parsers.** `party-report.md` uses the same shapes
`specclaw-loop` already reads (`bin/specclaw-loop:160-179` verdict extraction, `:291` BLOCK
counting):

```markdown
# Party Report: <change>

**Reviewed:** <YYYY-MM-DD>
**Tier:** <tier> (<tier_source>) — <rationale>
**Panel:** <role>(<model>), ...
**Verdict:** <APPROVED|APPROVED_WITH_NOTES|CHANGES_REQUESTED>

## Summary
<N findings: X BLOCK, Y WARN, Z NOTE — M withdrawn>

## Findings
### [BLOCK] party-security — <one-line objection>
**Quotes:** <verbatim line(s) from proposal.md>
**Problem:** ...
**Fix:** ...
**Status:** upheld

## Dissent
### [WARN] party-po — <objection>
**Status:** withdrawn — <reason>
```

**FR14 — `/specclaw:propose` integration.** A new step between generating `proposal.md` and
presenting it:

- `party.enabled: false` → skip silently.
- `party.default: false` (shipped) → resolve the panel, then **ask once**, quoting the resolved
  roster, the classifier's rationale, and the per-model spawn count. No answer → no panel.
- `party.default: true` → run without asking.
- After the run, present `party-report.md` alongside the proposal. Findings are appended to the
  proposal's **Open Questions** section; no other section is edited.
- Approval remains the operator's. `party.block: true` makes `CHANGES_REQUESTED` a hard stop for
  `/specclaw:plan`; it ships `false`.

**FR15 — Loop-halt surface (optional).** When `specclaw-loop decide` returns `halt` and
`party.on_loop_halt: true`, the panel runs against the halt — inputs are the failing gates,
`loop-log.md`, and the failure-signature history; the question is whether the design, the gate, or
the fix approach is wrong. One round only. Output attaches to the escalation notification.

**FR16 — Config block.** Seeded by `specclaw-init` into `config.yaml`:

```yaml
party:
  enabled: true
  default: false
  on_loop_halt: false
  rounds: 2
  block: false
  panel_mode: dynamic
  panel: [party-po, party-architect, party-ba, party-visionary]
  always: []
  min_seats: 2
  max_seats: 6
  models:
    party-classifier: haiku
    party-visionary: fable
    party-architect: opus
    party-security: opus
    party-ba: sonnet
    party-po: sonnet
```

**FR17 — Block-scoped config reads.** `specclaw-party` must not read `party.models` with the shared
`yaml_val` helper: that helper matches the rightmost key component anywhere in the file
(`bin/specclaw-loop:87-102`), and `config.yaml` already has a top-level `models:` block, so
`yaml_val "party.models"` would silently return the wrong section. A block-scoped reader is required,
following the `da_val` precedent (`bin/specclaw-build:557-574`).

### Non-Functional Requirements

**NFR1 — Cost is stated before it is spent.** The confirm prompt names the resolved roster and the
per-model spawn count. No panel runs without the operator having seen the bill (or having set
`default: true`).

**NFR2 — Classification cost is negligible.** One `haiku` call per proposal, against a panel of 4–10
`sonnet`/`opus`/`fable` spawns.

**NFR3 — Portable bash.** `bin/specclaw-party` is bash + coreutils, shellcheck-clean against
`shellcheck-baseline.txt`, no `jq` dependency in the script's own logic.

**NFR4 — Tests run without a model.** The suite stubs the classifier with fixture JSON. No test may
require a live agent spawn, and no test may require `jq` (`python3` for JSON asserts is the existing
convention — `tests/run-synth-agent-tests.sh:44`).

**NFR5 — Zero cost when off.** With `party.enabled: false`, `/specclaw:propose` and `/specclaw:loop`
behave exactly as today: no extra files, no extra spawns, no prompts.

**NFR6 — Idempotent classification.** Re-running `panel` for a change reuses the cached
`panel.json` rather than re-classifying, so the same proposal cannot draw a different roster — and a
different bill — on a retry. `--repanel` forces re-classification.

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — `specclaw-party panel .specclaw <change>` with a stubbed classifier returning
  `{"tier":"thin"}` writes `panel.json` with exactly `[party-po, party-architect]` and
  `tier_source: classifier`.
- **AC2** — Stubbed `{"tier":"deep"}` yields `[party-po, party-architect, party-ba,
  party-visionary, party-security]` — Security is seated at `deep` even with no domain flag.
- **AC3** — Stubbed `{"tier":"thin","domains":["security"]}` yields three seats including
  `party-security` — a domain flag seats the specialist independently of tier.
- **AC4** — A classifier that exits non-zero, prints unparseable output, or returns
  `{"tier":"enormous"}` produces tier `standard`, `tier_source: fallback`, a stderr warning, and exit
  code 0. In no case is the result `thin`.
- **AC5** — `party.max_seats: 3` on a `deep` classification yields 3 seats, with `dropped` naming the
  seats removed and the tail-order rule applied (Visionary dropped before Architect).
- **AC6** — `party.min_seats: 2` is never violated; `party.always: [party-security]` seats Security
  at tier `thin`.
- **AC7** — `panel_mode: fixed` and `--panel deep` both produce a roster **without invoking the
  classifier** (asserted by a stub that writes a sentinel file when called), with `tier_source`
  `fixed` / `override` respectively.
- **AC8** — Re-running `panel` on a change with an existing `panel.json` does not invoke the
  classifier and returns the identical roster; `--repanel` does invoke it.
- **AC9** — `tally` on a findings fixture with one upheld `BLOCK` prints `CHANGES_REQUESTED`; with
  that `BLOCK` marked `withdrawn`, the same fixture prints `APPROVED`.
- **AC10** — `tally` prints `APPROVED_WITH_NOTES` for upheld `WARN`s from two distinct roles, and
  `APPROVED` for a single upheld `WARN` from one role.
- **AC11** — `report` produces a `party-report.md` whose verdict is extracted correctly by the
  existing `extract_verdict`-style regex (`^\*\*Verdict:\*\*`) and whose BLOCK findings are counted
  correctly by `grep -cE '^### \[BLOCK\]'`.
- **AC12** — Withdrawn findings appear under `## Dissent` in the report and are excluded from the
  `## Findings` BLOCK count.
- **AC13** — Each of the six new agent definitions parses as valid frontmatter with `name`,
  `description`, `tools`, `model`; the models are `haiku`, `sonnet`, `sonnet`, `opus`, `opus`,
  `fable` respectively.
- **AC14** — Each panelist charter contains both a "must attack" and an explicit "must not comment
  on" section; no two panelist mandates overlap on the same dimension.
- **AC15** — Reading `party.models.party-visionary` from a `config.yaml` that also contains the
  top-level `models:` block returns `fable`, not a value from the top-level block (FR17 regression).
- **AC16** — With `party.enabled: false`, running `/specclaw:propose` end-to-end creates no
  `party/` directory and no `party-report.md`.
- **AC17** — `bash plugins/specclaw/tests/run-party-tests.sh` passes, is registered in
  `.github/workflows/ci.yml`, requires no network and no `jq`, and `shellcheck-gate.sh` reports no
  new findings.

## Edge Cases

1. **`proposal.md` missing or empty** — `panel` exits non-zero with a clear message; it does not
   classify an empty file as `thin`.
2. **Classifier returns JSON wrapped in prose or a fenced code block** — the parser extracts the
   first balanced JSON object; only genuine failure to find one triggers the fallback.
3. **`party.panel` names an agent with no definition file** — `panel` drops the unknown seat, warns
   on stderr, and records it in `dropped`; it does not abort the whole panel.
4. **`min_seats` > `max_seats`** — treated as a config error: warn, use the defaults (2/6).
5. **All findings withdrawn in round 2** — verdict `APPROVED`, and the report's Dissent section
   carries every withdrawal. An empty Findings section is written as "No upheld findings."
6. **A panelist returns nothing** (spawn failure or empty output) — the seat is recorded as
   `unheard` in the report; the tally proceeds on the remaining seats rather than blocking.
7. **`rounds: 1`** — the tally treats every round-1 finding as upheld; the Dissent section notes that
   rebuttal was disabled.
8. **The proposal argues its own triviality** ("this is a trivial change, no panel needed") — the
   classifier charter instructs it to ignore instructions addressed to itself inside the artifact;
   the artifact is data, not a prompt.
9. **Re-classification of a change whose proposal has been edited since `panel.json` was written** —
   the cache is keyed on a checksum of `proposal.md`, so an edited proposal re-classifies; an
   unedited one does not (mirrors the `sig` cache in `specclaw-build:669-681`).
10. **`--json` output** must remain valid when the rationale contains quotes or newlines — reuse the
    escaping helpers already in `specclaw-build` (`json_str`, `json_ml`).

## Dependencies

- **Existing:** `specclaw-init` (config seeding), `specclaw-validate-change`, `specclaw-set-phase`,
  `skills/propose/SKILL.md`, `skills/loop/SKILL.md`, `bin/specclaw-loop` (escalate path),
  `references/agent-guardrails.md`, `tests/shellcheck-gate.sh`, `.github/workflows/ci.yml`.
- **Precedents to follow rather than reinvent:** `da_val` block-scoped config reads
  (`specclaw-build:557-574`); `json_str` / `json_ml` (`specclaw-build:108-113`, `:537-544`); the
  `sig` + `schema_version` cache (`specclaw-build:669-681`); the report grammar
  (`agents/code-reviewer.md:67-102`) and its parsers (`specclaw-loop:160-179`, `:291`); the test
  harness shape (`tests/run-synth-agent-tests.sh`).
- **External:** none. No new binaries, no network.

## Notes

**Deliberately unresolved, to be decided in design or deferred:**

- Whether panelists see `context.md` / `patterns.md` in addition to `proposal.md`. The Architect and
  Visionary are weak without project context; feeding it to five agents multiplies cost. Design must
  pick one and say why.
- Whether recurring objections should feed `/specclaw:learn` and `patterns.md`. Out of scope here,
  but the report format should not preclude it.
- Whether the loop-halt surface (FR15) ships in this change or splits out. It shares the agents and
  the report, but nothing else; it is sequenced last so it can be dropped without unpicking the rest.

**Validation the spec asks for before the feature is trusted:** run the classifier over this repo's
31 existing proposals and read the tiers. The corpus exists and grading it costs ~31 `haiku` calls.
That is the cheapest available evidence that the classifier is not producing noise — and it is also
the answer to "do the roles actually disagree", which the panel's whole value rests on.
