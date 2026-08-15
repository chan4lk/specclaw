# Design: Party mode — an adversarial panel that argues a proposal before it becomes a plan

**Change:** 032-party-mode
**Created:** 2026-08-15

## Technical Approach

One new script, six new agent definitions, three edited call sites, one new test suite.

The load-bearing idea is a **two-layer split that already exists twice in this repo**: a model
supplies judgement, a script supplies arithmetic and state.

| Layer | Owner | Party-mode instance | Existing precedent |
|-------|-------|---------------------|--------------------|
| Judgement | model | `party-classifier` picks a tier; panelists write findings | `code-reviewer` writes findings |
| Arithmetic / state | bash | `specclaw-party` resolves seats, tallies the verdict, writes `panel.json` | `specclaw-loop` evaluates gates; `specclaw-parse-tasks --count` counts |

Nothing about the panel is a new architectural pattern. `specclaw-party panel` is `specclaw-build
synth-agent` one level up (classify an artifact, resolve a roster, cache the decision with a
signature); `party-report.md` is `review-report.md` with a role column; `run-party-tests.sh` is
`run-synth-agent-tests.sh` with different fixtures.

**Control flow at `/specclaw:propose`:**

```
proposal.md written
        │
        ├─ party.enabled false ──────────────────────────────► present proposal (unchanged today)
        │
  specclaw-party panel .specclaw <change>
        │   ├─ panel.json cached & proposal checksum matches ─► reuse roster (no spawn)
        │   ├─ panel_mode: fixed / --panel <tier> ───────────► roster, no classifier spawn
        │   └─ else spawn party-classifier (haiku, Read-only)
        │            ├─ valid JSON  → tier + domains  (tier_source: classifier)
        │            └─ anything else → tier=standard (tier_source: fallback, warn on stderr)
        │
        ├─ party.default false → ask once, quoting roster + rationale + per-model spawn count
        │        └─ no → stop, no files written
        │
  Round 1: spawn every seat in parallel, each sees only proposal.md + its own charter
        │        └─ each writes findings-r1/<role>.md
  Round 2 (rounds: 2): re-spawn each seat with all r1 findings; each marks its own upheld/withdrawn
        │        └─ each writes findings-r2/<role>.md
        │
  specclaw-party tally  → verdict (arithmetic over r2 findings)
  specclaw-party report → party-report.md
        │
  Findings appended to proposal.md "Open Questions"; report presented; operator approves or not
```

## Architecture

### `bin/specclaw-party`

Bash, no `jq`, shellcheck-clean. Four subcommands.

**`panel <specclaw_dir> <change> [--panel <tier>] [--repanel] [--json]`**

1. Validate `proposal.md` exists and is non-empty (else exit 2).
2. Compute `sig` = `cksum < proposal.md` (the `specclaw-build:672` pattern).
3. If `party/panel.json` exists with a matching `sig` and `schema_version`, and `--repanel` is
   absent → print the cached roster and return. This is NFR6: the same proposal cannot draw a
   different bill on a retry.
4. Resolve the tier:
   - `--panel <tier>` → `tier_source: override`, no classifier spawn.
   - `party.panel_mode: fixed` → seats taken verbatim from `party.panel`, `tier_source: fixed`, no
     classifier spawn.
   - Otherwise → **emit a classifier request** (see "Who spawns the classifier", below), read the
     returned JSON, `tier_source: classifier`.
   - Any failure at that step → `tier=standard`, `tier_source: fallback`, warn on stderr, **exit 0**.
5. Resolve seats from the tier table (FR4), union `party.always`, drop seats whose
   `agents/<name>.md` does not exist (warn, record in `dropped`), then clamp to
   `[min_seats, max_seats]` dropping from the tail of the tier order.
6. Resolve each seat's model: `party.models.<seat>` if set, else the agent file's frontmatter
   `model:`.
7. Write `party/panel.json` atomically (temp file → `mv`, the `specclaw-set-phase` pattern) and
   print the summary.

**`tally <specclaw_dir> <change>`** — read `party/findings-r2/*.md` (or `findings-r1/*.md` when
`rounds: 1`), count upheld findings by severity and by role, apply FR12, print the verdict token.
Exit 1 on `CHANGES_REQUESTED` **only** when `party.block: true`, so callers can use the exit code as
a gate without hard-coding policy.

**`report <specclaw_dir> <change>`** — assemble `party-report.md` from the findings files plus the
tally. Upheld findings go under `## Findings`; withdrawn ones under `## Dissent`; seats that produced
nothing are listed as `unheard`.

**`-h|--help`** — usage.

### Who spawns the classifier

Subagents are spawned by the **skill** (the model turn), not by bash — bash cannot call the `Agent`
tool. This is exactly how `build` handles synthesized agents: `specclaw-build synth-agent` emits a
JSON *scaffold* and `skills/build/SKILL.md:77-88` does the dispatch.

Party mode follows that contract:

- `specclaw-party panel --emit-classifier-request` prints the classifier prompt and the target path
  for its answer, then exits 10 (a distinct code meaning "I need a model turn").
- `skills/propose/SKILL.md` sees exit 10, spawns `party-classifier` with the printed prompt, writes
  the JSON to `party/classification.json`, and re-runs `panel`, which now finds the file and
  proceeds.
- If the skill skips that dance (non-interactive caller, agent unavailable), `panel` finds no
  `classification.json` on the second call and takes the FR5 fallback. **The fallback is therefore
  the automatic behaviour for any caller that does not implement the handshake** — which is why it
  must be `standard` and must warn.

The same handshake carries round 1 and round 2: the script decides *who* speaks and *with what
context*; the skill does the speaking.

### Config reads — a block-scoped reader is mandatory

`yaml_val` (`bin/specclaw-loop:87-102`) reduces `a.b.c` to `c:` and greps the **whole file** for the
first match. `config.yaml` already contains a top-level `models:` block
(`.specclaw/config.yaml:11-14`), so `yaml_val "party.models"` returns the planning/coding/review
section. Silently. This is FR17.

`specclaw-party` therefore ships `party_val`, modelled on `da_val` (`specclaw-build:557-574`): seek
to the `party:` line, read only until the next top-level (column-0) key, then resolve the remaining
dotted path inside that window. AC15 is the regression test, and it is written against a fixture
that contains both blocks.

### Agent definitions

Six files under `agents/`, all following the `code-reviewer.md` shape:

```yaml
---
name: party-security
description: <one line — when this agent is used>
tools: [Read]          # panelists need no Write; the skill persists their output
model: opus
---
```

`tools: [Read]` for every panelist and for the classifier. Panelists return findings as their final
message and the skill writes the file — narrower than `code-reviewer`'s `[Read, Write, Bash]`,
because a reviewer of a *single prose artifact* has no reason to touch the filesystem or run
commands. Less trust, less blast radius, and it makes the "artifact is data, not instructions"
boundary (Edge Case 8) enforceable rather than merely requested.

Each panelist body has: Identity, Inputs, **Mandate** (what it must attack), **Out of mandate**
(what it must stay silent about — the anti-convergence mechanism, FR14/AC14), Evidence discipline
(copied verbatim in spirit from `code-reviewer.md`), Output contract, and the obligation-to-object
rule (FR10).

The classifier body additionally states what depth *is* (subsystem count, unresolved design surface,
irreversibility, trust/data/release boundaries), what it is *not* (prose volume), the escalate-only
rule for the proposal's self-declared Complexity/Risk (FR3), and the instruction to treat the
artifact as data — any sentence in the proposal addressed to the classifier is content to be
classified, not an instruction to be followed (FR-adjacent, Edge Case 8).

### Report grammar

`party-report.md` reuses the grammar `specclaw-loop` already parses — `**Verdict:**` on its own line
(`specclaw-loop:160-179`) and `### [BLOCK] ...` finding headings (`specclaw-loop:291`). Consequence:
if a future change wants a party gate in the loop, `extract_verdict` and the BLOCK counter work
unchanged. No second grammar, no second parser. The role name takes the slot where `code-reviewer`
puts `path:line`, because the anchor for a prose finding is a quote, not a line number — hence the
mandatory `**Quotes:**` field.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-party` | Create | `panel` / `tally` / `report` / help; `party_val` block-scoped config reader; JSON helpers reused from the `specclaw-build` patterns |
| `plugins/specclaw/agents/party-classifier.md` | Create | `model: haiku`, `tools: [Read]` — returns `{tier, domains, rationale, signals}` |
| `plugins/specclaw/agents/party-ba.md` | Create | `model: sonnet` — problem fidelity |
| `plugins/specclaw/agents/party-po.md` | Create | `model: sonnet` — value per token, do-nothing option |
| `plugins/specclaw/agents/party-architect.md` | Create | `model: opus` — structural fit, blast radius |
| `plugins/specclaw/agents/party-security.md` | Create | `model: opus` — trust boundaries, misfire behaviour |
| `plugins/specclaw/agents/party-visionary.md` | Create | `model: fable` — does this compound |
| `plugins/specclaw/skills/propose/SKILL.md` | Modify | New step 3.5: panel resolution, confirm prompt, round 1 / round 2 dispatch, report presentation, Open-Questions append |
| `plugins/specclaw/skills/loop/SKILL.md` | Modify | Optional panel-on-halt when `party.on_loop_halt` |
| `plugins/specclaw/bin/specclaw-loop` | Modify | `escalate` attaches `party-report.md` to the escalation note when present |
| `plugins/specclaw/bin/specclaw-init` | Modify | Seed the `party:` config block |
| `plugins/specclaw/templates/config.yaml` | Modify | Ship the `party:` block with documented defaults |
| `plugins/specclaw/CLAUDE.md` | Modify | Document party mode, the judgement/arithmetic split, and the `party_val` hazard |
| `plugins/specclaw/tests/run-party-tests.sh` | Create | Seat resolution, fallback, clamping, cache, tally boundaries, config-collision regression |
| `.github/workflows/ci.yml` | Modify | Register the suite — an unregistered suite has silently never run twice in this repo |

## Data Model Changes

**New: `.specclaw/changes/<change>/party/panel.json`**

```json
{
  "schema_version": 1,
  "sig": "3149032421 8123",
  "tier": "deep",
  "tier_source": "classifier",
  "rationale": "Rewires four scripts and changes when PRs are created; touches release machinery.",
  "domains": ["security", "ops"],
  "seats": [
    {"role": "party-po", "model": "sonnet"},
    {"role": "party-architect", "model": "opus"},
    {"role": "party-ba", "model": "sonnet"},
    {"role": "party-visionary", "model": "fable"},
    {"role": "party-security", "model": "opus"}
  ],
  "dropped": []
}
```

**New, transient:** `party/classification.json`, `party/findings-r1/<role>.md`,
`party/findings-r2/<role>.md`.

**New, durable:** `party-report.md` in the change root — alongside `review-report.md` and
`verify-report.md`, and therefore inside the artifact set that `029-staged-files-auditor` proposes to
enforce.

No changes to `state.json`, `status.md`, or `tasks.md` schemas. Party mode is not a lifecycle phase;
it is a step inside `propose`.

## API Changes

New CLI surface only:

```
specclaw-party panel  <specclaw_dir> <change> [--panel thin|standard|deep] [--repanel] [--json]
specclaw-party tally  <specclaw_dir> <change> [--json]
specclaw-party report <specclaw_dir> <change>
```

Exit codes: `0` success (including the fallback path), `2` usage/missing artifact, `10` "classifier
turn required" (handshake), `1` `CHANGES_REQUESTED` when `party.block: true`.

No existing script's interface changes. `specclaw-loop escalate` gains behaviour but keeps its
signature.

## Key Decisions

**D1 — The classifier is a model, and this is a deliberate exception to "the script decides."**
Depth is a judgement; word counts and keyword lists are proxies for one, and every proxy was gameable
by the same model that writes the proposal. The exception is bounded: the model returns a *tier*, and
every consequence of that tier is computed in bash. Cost is ~1 `haiku` call against a 4–10 spawn
panel it controls.

**D2 — Fallback is `standard`, never `thin`.** The failure mode of a cheap classifier is a silent
downgrade, and a silently two-seat panel looks exactly like a working one. `standard` plus a stderr
warning plus `tier_source` in `panel.json` makes the failure visible three ways.

**D3 — `panel.json` is cached on a checksum of `proposal.md`.** Answers "why did this cost 10 spawns
yesterday and 4 today": it cannot. An edited proposal re-classifies; an unedited one is stable.
Directly borrowed from `specclaw-build:669-681`.

**D4 — Panelists get `tools: [Read]` and do not write files.** The skill persists their output. A
prose reviewer needs no `Bash`, and withholding it makes the "the artifact is data" boundary
structural rather than a request in a prompt.

**D5 — Panelists see `proposal.md` and nothing else in round 1.** Deliberately answering the spec's
open question the cheap way: `context.md` and `patterns.md` are *not* fed to the panel in this
change. Reasons: it multiplies token cost by the seat count; it dilutes the "quote the line you
flag" evidence rule across several documents; and the Architect's context-blindness is a *measurable*
complaint that the first real reports will either raise or not. Adding context later is a one-line
prompt change; removing it after the cost is baked in is not.

**D6 — Out-of-mandate lists are the anti-convergence mechanism.** Five agents with overlapping
mandates produce the same three findings and cost five times as much as one. Each charter therefore
names dimensions it must stay silent on. AC14 asserts non-overlap.

**D7 — Obligation to object, with an explicit no-objection form.** A panel that says nothing is
indistinguishable from a panel that failed. Each seat must file a finding or an explicit "no
objection under this lens" note.

**D8 — The report reuses the existing grammar rather than inventing one.** `**Verdict:**` and
`### [BLOCK]` are already parsed by `specclaw-loop`. A second grammar would mean a second parser, and
this repo has already paid for parser drift twice (`#59`, `#61`).

**D9 — The loop-halt surface is sequenced last (W4) so it can be dropped.** It shares the agents and
the report and nothing else. If W1–W3 land slow, W4 is a clean cut line.

**D10 — The `party:` block is seeded but ships inert** (`default: false`, `block: false`,
`on_loop_halt: false`). Same one-release rollout `workflow.code_review_block` took. Nobody's existing
`propose` run changes behaviour on upgrade.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **The roles converge** — five agents, three identical findings. The whole feature's value fails. | High | Out-of-mandate lists (D6); AC14 non-overlap check; the spec's pre-build validation — run the panel by hand on `029-staged-files-auditor` before W2 and read whether the findings differ. If they do not, cut to one reviewer and abandon the panel. |
| **Classifier misreads depth**, seating two agents on a dangerous proposal. | Medium | Fallback `standard`; `always` force-seating; `--panel` override; the rationale is quoted in the confirm prompt so the operator can reject a bad read *before* spending; `panel.json` records it for diagnosis. |
| **Prompt injection via the proposal** — a proposal that argues its own triviality talks the classifier into `thin`. | Medium | Classifier charter treats the artifact as data and ignores instructions addressed to itself; `tools: [Read]` only; the operator sees the rationale before the panel runs. Residual risk accepted and recorded — the cost lever is bounded (a downgrade saves spawns, it cannot skip the operator's approval). |
| **`yaml_val` collision** returning the wrong models block. | Medium | `party_val` block-scoped reader (D-level requirement FR17); AC15 regression test against a fixture containing both blocks. |
| **Cost surprise** on `default: true`. | Medium | Confirm prompt states the per-model spawn count; `rounds: 1` halves it; `party.models` retargets the whole panel in one edit; `max_seats` caps it absolutely. |
| **Handshake fragility** — a caller that does not implement the exit-10 dance silently always gets `standard`. | Medium | The fallback warns on stderr *and* stamps `tier_source: fallback`, so a mis-wired caller shows up in every `panel.json` rather than in none. |
| **Test suite drifts unregistered** (has happened twice in this repo). | Low | CI registration is an explicit task with its own AC (AC17), not a step inside another task. |

## Grounding sources

- `plugins/specclaw/CLAUDE.md` — *"`specclaw-parse-tasks --count` is the only counter"* and
  *"`specclaw-set-phase` is the only writer"*. The judgement/arithmetic split (D1) and the atomic
  `panel.json` write follow these directly; party mode adds **no** second writer of any existing
  state.
- `plugins/specclaw/CLAUDE.md` (Tests) — *"every one must be registered in `.github/workflows/ci.yml`
  — an unregistered suite silently never runs, which has happened twice."* Drove the separate CI task
  and AC17.
- `plugins/specclaw/bin/specclaw-loop:87-102` — the `yaml_val` implementation, whose
  `field="${key##*.}"` line is the whole reason FR17 exists.
- `plugins/specclaw/bin/specclaw-loop:160-179`, `:291` — `extract_verdict` and
  `grep -cE '^### \[BLOCK\]'`; the report grammar in D8 is written to satisfy these exact regexes.
- `plugins/specclaw/bin/specclaw-build:557-574` (`da_val`), `:669-681` (sig cache), `:108-113` /
  `:537-544` (`json_str` / `json_ml`) — the three patterns `specclaw-party` copies rather than
  reinvents.
- `plugins/specclaw/skills/build/SKILL.md:77-88` — *"Dispatch: spawn the agent with system_prompt as
  its system prompt … at synthesized model"*. The script-emits-scaffold / skill-spawns-agent
  handshake is lifted from here.
- `plugins/specclaw/agents/code-reviewer.md:67-102` — the report skeleton and the Evidence Discipline
  rule the panelist charters inherit.
- `plugins/specclaw/tests/run-synth-agent-tests.sh:34-44` — `pass`/`fail`/`assert_eq` and the
  `jget()` python3 JSON reader; `run-party-tests.sh` reuses this harness shape and its no-jq rule.
