---
description: Mandatory design-approval stage for a brownfield rebuild that decided SQ-013 REINTERPRET; inert otherwise. Briefs a redesigned prototype and gates the new repo on the client's approval (PROTOTYPE: READY). Run after /specclaw:bf-blueprint, when SQ-013 is REINTERPRET.
---

# specclaw bf-prototype

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Run this in the **legacy repo**, after `/specclaw:bf-blueprint`.

**This stage exists only under `REINTERPRET`, and under `REINTERPRET` it is mandatory.** A project that decided `FAITHFUL`, `THEME-ONLY`, or has not decided `SQ-013` at all sees nothing: this command stops with a one-line reason and writes nothing, and every other command behaves exactly as it did before this command existed. Under `REINTERPRET` the whole new-repo side is locked until this command prints `PROTOTYPE: READY` — `/specclaw:bf-bootstrap` will not scaffold and `/specclaw:propose` will not draft.

**What this command is, and is not.** It owns the **records** and the **gates**: the legacy-screen → prototype-screen map, the permanent `PS-###` ids, the questions a redesign raises, the approval join, the bash-computed readiness, and the tamper-evident manifest. It does **not** contain a UI generator and never will. A separate prototype/UI skill — named in `config.yaml`'s `prototype.skill` — builds the prototype, in the framework **and** language the project decided.

**The prototype is design-acceptance code and is thrown away.** It is built in the real target stack so the client approves realistic component behaviour and the production team can read it as a reference. It is never copied to the new repo, never a `/specclaw:bf-bootstrap` input, and `--adopt` refuses it by hash. Only the map, the manifest and the screenshots travel.

Determine the mode from the user's message:

| If the message contains | Mode |
|---|---|
| `--record` | **Mode C** — hash, join approvals, compute readiness |
| `--brief-only` | **Mode B** — brief only; the prototype is built elsewhere |
| neither | **Mode A** — brief and generate (default) |

## Mode A — brief and generate (default)

### 1. Collect

```bash
mkdir -p .specclaw/analysis/.collect
specclaw-bf-prototype collect .specclaw > .specclaw/analysis/.collect/prototype.json
```

Deterministic, no agent, writes nothing beyond that collected-facts file. **Check the exit status before spawning anything below, and never hand the agent a path to a half-written file.** It resolves the preconditions in order and **stops on the first one that fails, naming the exact id or file**:

- `SQ-013` decided `REINTERPRET` — otherwise this stage does not apply.
- The **frontend framework** and the **frontend language**, each resolved from the decision record with a citation (`SQ-006` and `SQ-015`, or a `DECIDED` frontend row in `target-architecture.md`, or both in one answer written `<framework> (<language>)`).
- `ui-inventory.md`, `rebuild-backlog.md`, `target-architecture.md`.

**Surface its stderr verbatim and stop** in every one of those cases. Two are worth recognising on sight:

- **`framework: SQ-006 undecided`** — the rebuild has not chosen a UI framework.
- **`language: no decided SQ/CQ names the frontend language`** — the more common one, and the whole reason `SQ-015` exists. A framework name decides a framework and nothing else. **Never suggest a language, and never let the user's framework choice imply one** — the fix is to raise it in `/specclaw:bf-clarify` (with an options pack if the choice is the client's), answer it by name, `--resolve`, re-run `/specclaw:bf-blueprint`, then re-run this command. Answering `SQ-006` as `<framework> (<language>)` with the language as a single bare word decides both at once.

If `config.yaml` has no `prototype.skill`, or the named skill cannot be located: **stop, show the raw output of what you searched, and ask which skill to configure.** Never pick one.

### 2. Spawn the agent

`Agent` tool, `subagent_type: "bf-prototype-architect"`. Pass the path `.specclaw/analysis/.collect/prototype.json` — it reads that file directly — the project root, and the two paths it may write: `.specclaw/prototype/prototype-brief.md` and (append-only) `.specclaw/analysis/pending-questions.md`.

Tell it explicitly that it may not choose a framework or a language, may not allocate a `CQ-###`, and may not write `prototype-approvals.md`.

The agent allocates its ids through `specclaw-bf-prototype allocate` — the only place a `PS-###` is ever minted.

### 3. Hand off to the prototype skill

The agent invokes the configured skill with the brief's hand-off block. **If that skill cannot build in the decided framework, or cannot build in the decided language, stop and report it.** Never substitute either, and never fall back to a stack the skill finds easier: a prototype in a different framework or language is not the design anybody is approving.

### 4. Report the questions

If the run raised any `PQ-###`, say so plainly and name them. They are the behaviour changes the redesign proposes, and each one blocks its screen from ever being computed `APPROVED` until a human decides it. Offer the loop:

```
/specclaw:bf-clarify           → promotes the PQ to a CQ (Blocking: yes)
  → a human answers it by name
/specclaw:bf-clarify --resolve
/specclaw:bf-rebuild-plan --refresh → /specclaw:bf-blueprint → re-run /specclaw:bf-prototype
```

The `PS-###` keeps its id through all of it; the `PROVISIONAL` marker clears itself once the question is decided.

## Mode B — brief only (`--brief-only`)

Identical to Mode A through step 2, then stop. Tell the user to build the prototype externally — **in the same decided framework and language** — and import it into `prototype.output_dir` before running `--record`. An empty output directory makes `--record` exit `2` with `prototype.output_dir is empty`, which means "nothing has been imported yet", not "the design was rejected".

## The two human steps

Neither is yours. Say so plainly rather than offering to do them.

**1. Put the prototype in front of the client.** For each screen, capture one screenshot into `.specclaw/prototype/screens/`, named by its `PS-###` (`PS-001.png`).

**2. Record each verdict, by name.** In `.specclaw/prototype/prototype-approvals.md`, one row per screen:

```
| PS-001 | APPROVED | Mira Costa | 2026-09-16 | <tree_hash from the --record run they reviewed> |
```

Verdict is `APPROVED`, `CHANGES-REQUESTED` or `REJECTED`. The hash is the `tree_hash` printed by the `--record` run the approver actually looked at — that is what binds an approval to a specific prototype, so editing the prototype afterwards turns the screen `STALE` rather than leaving a stale sign-off standing.

**No agent and no script ever writes this file.** Do not offer to fill it in, do not supply a name, and do not record an approval the user reports verbally without them writing it themselves. An approval a tool can write is not an approval.

## Mode C — record (`--record`)

```bash
specclaw-bf-prototype record .specclaw
```

Hashes `prototype.output_dir` into one `tree_hash`, sha256s every screenshot, joins the approvals, applies the status precedence, computes readiness against the rebuild backlog, writes `prototype-manifest.json`, and prints a raw line on stdout:

```
PROTOTYPE: READY
PROTOTYPE: NOT-READY (PS-003 (STALE), SCR-007 uncovered)
```

Exit `0` = READY, `1` = NOT-READY, `2` = nothing to record.

Then render the map:

```bash
specclaw-bf-prototype map-render .specclaw .specclaw/prototype/.map-draft.txt
```

The agent writes only the narration paragraph to that draft path; bash renders every row.

**Report the readiness line exactly as bash printed it.** Never infer a status, never upgrade one, and never describe a `NOT-READY` prototype as ready-pending-something. Statuses are computed in this precedence, first match wins:

| | Condition | Status |
|---|---|---|
| 1 | an unresolved `PQ`/`CQ` is referenced | `PROVISIONAL` |
| 2 | `APPROVED` but the tree hash has changed | `STALE` |
| 3 | `CHANGES-REQUESTED` | `CHANGES-REQUESTED` |
| 4 | `REJECTED` | `REJECTED` |
| 5 | `APPROVED` and the hash matches | `APPROVED` |
| 6 | a screenshot exists, no approval row | `IN-REVIEW` |
| 7 | otherwise | `DRAFT` |

Rule 1 outranking a human `APPROVED` is deliberate: an undecided behaviour question means nobody has agreed to the change the redesign proposes, whoever signed the screen off.

`prototype_ready` is true when every `SCR-###` that an in-scope, active, screen-bearing backlog item renders is covered by at least one `APPROVED` screen — or is retired by a decided `CQ`, or recorded out of scope by the backlog — with none of those screens `STALE` or `PROVISIONAL`, and the recorded framework and language still matching what the decision record resolves.

Screens the client scoped out never block. That is why readiness is measured against the backlog and not the legacy inventory.

## When it is ready

`PROTOTYPE: READY` is the ticket into Phase B. Then, and only then, copy these three together into the new repo:

- `.specclaw/prototype/prototype-map.md`
- `.specclaw/prototype/prototype-manifest.json`
- `.specclaw/prototype/screens/`

**Never copied:** `app/`, `prototype-brief.md`, `prototype-approvals.md`, `id-registry.json`. The manifest carries the review points precisely so the new repo needs nothing from the brief.

The manifest and `screens/` always travel together, or the recorded hashes prove nothing — the same pairing rule `ui-manifest.json` and `.specclaw/ui/screens/` follow.

A `NOT-READY` manifest copied early is inert and blocks everything: `/specclaw:bf-bootstrap` refuses to scaffold and `/specclaw:propose` refuses every item. That is the intended behaviour, not a bug to work around.

## Troubleshooting

| Symptom | What it means |
|---|---|
| `UI fidelity policy is FAITHFUL/THEME-ONLY/UNDECIDED, not REINTERPRET` | This stage does not apply. Nothing was written. |
| `framework: SQ-006 undecided` | Decide the UI framework in `/specclaw:bf-clarify`. |
| `language: no decided SQ/CQ names the frontend language` | Decide it by name (`SQ-015`), or write `SQ-006` as `<framework> (<language>)`. It is never defaulted. |
| `framework: … and … disagree` | `decisions.md` and `target-architecture.md` hold different values. Fix whichever is stale; this command will not pick. |
| `prototype.output_dir is empty` (exit 2) | Nothing has been built or imported yet. Not a rejection. |
| `NOT-READY (SCR-### uncovered)` | An in-scope screen has no approved prototype screen. |
| A screen reads `STALE` | The prototype changed after sign-off. Re-approve against the new `tree_hash`, re-record, re-copy. |
| Approved but still `PROVISIONAL` | An undecided behaviour question blocks it. Decide the `PQ`/`CQ`. |
| `NOT-READY (stack-decision-changed: framework\|language)` | The stack decision moved after approval. Regenerate and re-approve. If you changed a decision and changed it straight back, re-run `--record` once more — the first run reports the change it saw, the next settles. |
| A screen reads `RETIRED` | Its `PS-###` is in the registry but it is no longer briefed. Informational; it never blocks. |
| `prototype.skill` unset | Configure it. Never pick one on the user's behalf. |

## Next step

**Only if this run completed.** Every mode has steps that say to surface stderr and stop. A run that did not finish must never print a next step.
