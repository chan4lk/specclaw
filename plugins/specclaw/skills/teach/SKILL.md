---
description: Turn teaching mode on or off, record what the human already knows, and generate on-demand concept briefs. When teach mode is enabled, propose/plan/build/verify explain before implementing and surface design choices as decisions for the human instead of deciding silently. Use when a user wants to learn the technologies while a change is built, or asks to be walked through rather than handed finished code.
---

# specclaw teach

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized; auto-inits using the current directory's basename as the project name).

Teaching mode makes the lifecycle **explain while it builds**. It does not add a parallel workflow —
`propose`, `plan`, `build` and `verify` gain teaching behaviour when it's on, and behave exactly as
before when it's off.

Full protocol: `references/teaching-mode.md`. Read it before running a teaching phase.

> **Not to be confused with `/specclaw:learn`**, which records what the *machine* learned — spec
> gaps and patterns fed back into agent context. This skill teaches the *human*.
> `learnings.md` and `teaching.md` are the two halves.

## Invoked with no arguments? Run the assessment.

**This is the default behaviour and it is not optional.** A bare `/specclaw:teach` means *"assess me
and show me the plan"* — not *"print the config"*. Reporting status and stopping is the failure mode
this section exists to prevent.

```bash
specclaw-teach .specclaw status    # enabled, depth, gate_builds
specclaw-teach .specclaw assess    # what still needs asking
```

`assess` returns `recorded`, `self_reported`, `needs_confirmation` (levels marked `assumed`),
`unknown_provenance` (older rows with no source), and whether a learning plan exists.

Then run these five steps in order:

### Step 1 — Show the whole stack first, as a table

**Before asking anything, show them what they're dealing with.** Read the change's `proposal.md`,
`spec.md`, `design.md`, `tasks.md`, plus `package.json` / compose files / lockfiles for the concrete
libraries. Then present **every** technology the work touches:

| # | Technology | What it's for *here* | Where it appears | Your level |
|---|-----------|---------------------|------------------|-----------|
| 1 | Kafka | The event bus all four services publish to | T1, T3, T5 | ? |
| 2 | kafkajs | The Node client — the actual API you'll read | T3, T4 | ? |

Rules for this table:
- **Include libraries, not just categories.** "Kafka" and "kafkajs" are different things to know;
  so are "tracing" and "the OTel SDK". Vague rows produce vague levels.
- **Include what's already recorded**, showing the level rather than `?`. They need the whole
  picture, not the gaps.
- **"What it's for here"** is project-specific, not a definition. `"The event bus all four services
  publish to"`, not `"a distributed streaming platform"`.
- Order by when it's first needed.

This table is half the value of the whole skill: it's the first time the learner sees the actual
surface area of the work.

### Step 2 — Ask about every row

**Ask across the whole stack, not just the gaps.** Being asked is not overhead — it's how the
learner discovers what the project involves. `AskUserQuestion` takes 4 per call, so batch by
first-needed order and say how many batches are coming.

- **(a)** never used it · **(b)** theory / tutorials only · **(c)** shipped something real · **(d)** deep

For rows already marked `self` and recorded recently, don't re-ask from scratch — show the recorded
level and ask for confirmation in a single question covering several rows at once.

```bash
specclaw-teach .specclaw level kafkajs a self
```

If a profile came pre-populated and you cannot tell who answered, **ask again** — a profile you
inherited is not an assessment.

**Spot-check every (c)/(d) claim** with one specific, answerable question, and correct the level
silently if it doesn't hold. Say you're correcting it and why. The aim is a correctly calibrated
plan, not a score — and an honest downgrade buys them the teaching they'd otherwise have been
denied.

### Step 3 — Show the level map back
Technology, level, source, and **what that means for their time** — brief / production-concerns only
/ no teaching / you-lead. They should see where the hours will go before agreeing to spend them.
Call out the ratio: *"five of eight at (a)/(b), which is why briefs go one-per-task rather than as a
reading pile."*

### Step 4 — Generate the learning plan
```bash
specclaw-teach .specclaw plan-path      # canonical location
```

Write it from `templates/knowledge/learning-plan.md`, filling all eight sections:

| Section | Contents |
|---------|----------|
| 1 Level map | Every technology, level, source, treatment |
| 2 **Learn** | One brief per (a)/(b) technology, each tied to the task that needs it — *not* delivered up front |
| 3 **Explain** | Every decision that is theirs, with the task it blocks |
| 4 **PoC** | Only where watching a mechanism fail is faster than reading about it. Justify each; skip the rest |
| 5 Implementation | The build sequence, marking which waves gate and what their part is (decide / predict / observe) |
| 6 **How to start** | One concrete opening move — see step 5 |
| 7 Predictions | Empty, filled as you go |
| 8 Not learning | What's deliberately skipped, and why |

The plan is derived from the level map. Someone at (d) on Docker gets no Docker entries at all;
someone at (a) on Kafka gets a brief, possibly a PoC, and a gate.

**Align it to the specclaw lifecycle, not to an abstract syllabus.** Every learning item hangs off a
real phase, wave or task id — `T5`, `wave 2`, `/specclaw:verify` — so "learning" and "the work" are
the same list. If an item can't be attached to a task, either it belongs in section 7 (not learning
this time) or the plan is missing a task.

### Step 5 — Suggest how to start

Don't end with a menu. End with **one concrete opening move**, and say what it opens with:

> **Start with T1 (Kafka + Jaeger containers).** It opens with the Kafka brief — partitions,
> offsets, consumer groups — then the one decision that gets expensive later: partition key.
> Everything else in wave 1 is Compose, which I write without commentary.
>
> Say **"start T1"** and I'll open with the brief.

Name the first thing, why it's first, what teaching it opens with, and the exact words to reply.
"Approve the plan or tell me what to change" is a menu, not a suggestion.

## Toggle

```bash
specclaw-teach .specclaw enable --depth brief      # minimal | brief | full
specclaw-teach .specclaw disable
```

`depth` controls how much explanation each phase offers:

| depth | Behaviour |
|-------|-----------|
| `minimal` | Decisions surfaced as options; no concept briefs |
| `brief` | + a 3-minute brief before any phase using a technology rated **a** or **b** *(default)* |
| `full` | + a prediction before every measurement, and a debrief after `verify` |

## Levels

```bash
specclaw-teach .specclaw level kafka a self       # they answered
specclaw-teach .specclaw level docker d assumed   # inferred - must be confirmed later
specclaw-teach .specclaw levels
```

Project-wide, in `.specclaw/knowledge/learner-profile.md`. The fourth argument is provenance and it
is load-bearing:

| Source | Meaning | Consequence |
|--------|---------|-------------|
| `self` | The learner answered | Trusted; phases act on it |
| `assumed` | You inferred it | **Must be re-asked** before any phase relies on it. `assess` lists these |

Default is `self`, so only pass `assumed` when you're guessing. Recording a guess as `self` is the
bug that makes teaching mode silently skip someone's assessment.

Ask in **batches covering the next one or two phases only** — twelve questions up front is its own
kind of overwhelm. Re-ask whenever a change introduces a technology not already in the profile.

## Log what was taught

```bash
specclaw-teach .specclaw <change> log brief      "Kafka: log vs queue, offsets, consumer groups"
specclaw-teach .specclaw <change> log decision   "Chose orchestration over choreography — easier to trace"
specclaw-teach .specclaw <change> log prediction "Predicted p95 250ms; measured 310ms; gap = broker fsync"
specclaw-teach .specclaw <change> log checkpoint "Explained why at-least-once forces idempotency"
specclaw-teach .specclaw <change> log debrief    "Reviewed 6 decisions; overruled the DLQ retry count"
specclaw-teach .specclaw <change> --list
```

Writes to `.specclaw/changes/<change>/teaching.md`. That file *is* the evidence of learning — it's
what a mentor, reviewer, or the learner themselves reads three weeks later.

## Generate a concept brief

Do **not** ship or expect a cheatsheet library — a file per technology is a coverage promise no
plugin can keep, and static files rot while model knowledge doesn't. Generate briefs on demand
following the recipe in `references/teaching-mode.md`:

1. **Classify the topic.** Stable concept (saga, idempotency, CAP) → write from your own knowledge.
   Volatile specifics (versions, CLI flags, config keys, API signatures) → **fetch the official docs
   first**, and say you did.
2. **Six parts, in order:** the problem it solves → mental model *and where the analogy breaks* →
   3–5 primitives → **the numbers** → the failure mode → what it costs.
3. **Cache it** at `.specclaw/knowledge/briefs/<topic>.md`, stamped with the date and the version
   described. Never write it into the plugin.
4. **One to two screens.** Longer means it's two briefs — give the first, offer the second.

End every brief with one question that makes the user predict, decide, or explain something back.
Never "does that make sense?" — it invites yes.

## The two rules the phases enforce

**1. The human makes the decisions; the agent writes the code.** Hand-typing boilerplate teaches
nothing. Choosing between two designs *with the costs visible* is the skill being learned. So never
ask the user to type code "to learn"; ask them to decide, predict, or explain.

**2. One artifact at a time.** Documents are written at the phase that needs them, never in advance,
and every reply ends with exactly **one** next action. If the user seems lost, **shrink the step** —
adding explanation is the wrong fix for overwhelm.

## Phase behaviour when enabled

| Phase | Teaching behaviour |
|-------|--------------------|
| `propose` | Names the technologies the change will touch; asks for levels not yet in the profile |
| `plan` | Surfaces design decisions as 2–4 options with pros, cons and costs. The user picks; their reason is recorded verbatim in `design.md` |
| `build` | Before a wave using a technology rated a/b: offer a brief. After each wave: one verify command, what to expect, what it means |
| `verify` | Asks for a prediction before revealing numbers; logs predicted-vs-actual |
| `pr` | Debrief: what was built, every decision with its alternatives and costs, and how they'd build it from scratch |

When `teach.enabled` is false, none of the above happens and no teaching files are created.
