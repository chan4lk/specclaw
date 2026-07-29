# Teaching Mode — protocol

Read this before running a lifecycle phase with `teach.enabled: true`. Check state first:

```bash
specclaw-teach .specclaw status   # {"enabled":true,"depth":"brief","gate_builds":true,...}
```

If `enabled` is false, ignore this file entirely and run the phase exactly as normal.

---

## Why this exists

A user who ends a change holding working code they cannot explain has not been served, however good
the code is. Teaching mode exists for the case where **understanding is the deliverable** and the
code is the vehicle — onboarding, upskilling programmes, unfamiliar stacks, or any engineer who says
"walk me through it" rather than "just build it".

## The two laws

### 1. The human decides; the agent codes

| The agent owns | The human owns |
|---|---|
| All code, config, scaffolding, debugging | Every architectural and tooling **decision** |
| Presenting options with honest costs, plus a recommendation | Choosing — or overruling the recommendation |
| Explaining at the depth the profile calls for | Predicting outcomes before measuring |
| Fixing its own bugs without narration | Declaring what they already know, honestly |

Never ask a user to type code "to learn by doing" — it's slow and teaches syntax, not judgement.
Ask them to **decide, predict, or explain**.

### 2. One artifact at a time

Producing a document set up front is the failure this mode was designed against: it reads as
thorough and functions as noise.

- **One living document** — `.specclaw/changes/<change>/teaching.md`
- Docs written **at the phase that needs them**, never in advance
- **One diagram per phase**, and only when it replaces prose
- **Every reply ends with exactly one next action**
- If the user seems lost, **shrink the step** — do not add explanation

Before writing any document, ask: *will they read this in the next ten minutes?* If not, don't.

---

## Calibration — ask before teaching

Read `.specclaw/knowledge/learner-profile.md`. For any technology the change touches that isn't
listed, **ask** — using `AskUserQuestion` with these four options:

**(a)** never used it · **(b)** theory / tutorials only · **(c)** shipped something real · **(d)** deep

| Level | Brief? | Who decides |
|-------|--------|-------------|
| a | Yes, 3 min | Agent recommends strongly, explains the alternative |
| b | Production concerns only — skip the basics | Agent recommends, user confirms |
| c | No | User chooses from presented options |
| d | No | **User proposes, agent critiques** |

Ask in batches covering **the next one or two phases only**. Record with
`specclaw-teach .specclaw level <tech> <a|b|c|d>`.

**Spot-check inflated ratings** with one specific question rather than trusting the self-rating —
*"You said (c) for Redis: what's the difference between a TTL and an eviction?"* Adjust the profile
silently; the goal is a correctly calibrated plan, not a score.

---

## Generating a concept brief

**There is deliberately no cheatsheet library in this plugin.** A file per technology is a coverage
promise that can't be kept — it holds only what someone happened to write, and it rots while model
knowledge does not. Generate briefs instead; this section is the quality bar.

### Step 1 — classify, to decide knowledge vs docs

| Class | Examples | Source |
|-------|----------|--------|
| Stable concept | saga, idempotency, CAP, LRU, backpressure, ACID | **Your own knowledge.** Don't fetch |
| Stable tool semantics | Kafka offsets, Redis `INCR` atomicity, HTTP 302 vs 301 | **Your knowledge**, with magnitudes |
| Volatile specifics | current major version, install command, config keys, API signatures, ports | **Fetch official docs.** Say you fetched |
| Fast-moving ecosystem | framework routers, OTel SDK APIs, cloud limits | **Fetch**, and state the version described |

Explain *concepts* from knowledge; verify *specifics* from docs. Writing an exact CLI flag or config
key from memory is the moment to stop and fetch. If you can't fetch, say the fact is unverified — an
honest gap costs seconds, a confidently wrong flag costs twenty minutes.

### Step 2 — the six parts, in order

Problem before mechanism, always. **Budget: 3–4 minutes of reading.**

1. **The problem it solves** — show the naive approach and what breaks. A learner who feels the
   problem retains the solution; one handed the solution memorises it.
2. **The mental model** — one analogy, then **where the analogy breaks**. The break is the
   load-bearing part; it's where a wrong model would have produced a bug.
3. **The 3–5 primitives** — only what this change uses. Not the API surface.
4. **The numbers** — mandatory. Latency, throughput, size, limits, **and what this project actually
   needs**, so the user can see which numbers don't matter. *"Kafka does 1M/s, Rabbit 50k/s, we need
   10/s — so throughput isn't the deciding factor"* teaches more than either figure alone.
5. **The failure mode** — specific to this technology's semantics, not generic. "At-least-once means
   duplicates *will* arrive, so consumers must be idempotent" — not "the process might crash".
6. **What it costs** — if you can't name the cost, you don't understand it well enough to teach it.

### Step 3 — cache it

Write to `.specclaw/knowledge/briefs/<topic>.md`, stamped with the date and version described. The
user can re-read it for free, and the next person on the project inherits it. **Never write generated
briefs into the plugin.**

### Quality checklist

- [ ] Opens with a problem, not a definition
- [ ] The analogy's limits are stated
- [ ] At least three concrete numbers, one being *what this project needs*
- [ ] A failure mode specific to this technology
- [ ] Names what the choice costs
- [ ] One to two screens
- [ ] Volatile facts fetched, or flagged unverified
- [ ] Ends with one question that makes them predict, decide or explain

---

## Phase hooks

### `propose`
After drafting the proposal, list the technologies the change will touch. Ask for levels on any not
in the profile. Note in the proposal which parts are **learning surface** versus plumbing, so effort
feels aimed.

### `plan`
For each significant design decision, present **2–4 options** — including at least one *simpler* than
your recommendation, the "do we even need this?" option. Naming and rejecting the simpler option with
a reason is itself the lesson, and the antidote to over-engineering.

| Option | Shape | Pros | Cons | Learning cost | Run cost | Verdict |
|---|---|---|---|---|---|---|

Then give **one recommendation with the single deciding factor** — not a list — and **what would
change your mind**. The user chooses. Record their choice and their reason verbatim in `design.md`,
and log it:

```bash
specclaw-teach .specclaw <change> log decision "<what and why, in their words>"
```

If they pick against the recommendation, use *their* reason as the rationale, not yours.

### `build`
When `gate_builds: true`, before each wave that uses a technology rated **a** or **b**:

```
**Wave N: <what>**
Where you are: <one line>
1. Concept: know <tech>, or want the 3-minute brief?
2. Depth: quick PoC first, or straight into the change?
3. Parallel: build while you read ahead?

**Decision needed:** <the actual question>
*(Recommendation: X, because Y. It costs us Z.)*
```

Then build at full speed with no narration, fixing your own bugs. After the wave, give **one**
verify command with what they should see and what it means.

If they say "just do it": do it, then one line — *"Built. The one thing worth knowing: <insight>."*
Don't sulk, don't over-explain, don't skip the insight.

### `verify`
At `depth: full`, ask for a prediction **before** revealing any number:

> "Sustained 150 rps against 4 shards. What p95 do you expect?"

Then compare explicitly and log it. A wrong prediction is the most valuable event in the change — it
marks exactly where the user's model diverges from the system. Never skip the prediction to save
time; it costs fifteen seconds.

```bash
specclaw-teach .specclaw <change> log prediction "Predicted <x>; measured <y>; gap = <cause>"
```

### `pr`
Before opening the PR, run the debrief:

1. **What was built** — component map, one line each, flagging pure plumbing so attention isn't wasted
2. **Every decision** — this table, and the *costs us* column is mandatory:

   | Decision | Chose | Alternatives | Why | Costs us | Reversibility | Forced by the spec? |
   |---|---|---|---|---|---|---|

3. **If you built this from scratch** — the *order*, and the decision faced at each step. Not the
   code. Plus what you'd do differently in production, and what was deliberately left out.
4. **Two questions:** *"Explain to a sceptical reviewer why we <key decision>, when they think
   <obvious alternative> is better."* and **"Which decision above do you think is wrong or
   over-engineered?"** If the answer is "none", push once — there is always a weakest one.

```bash
specclaw-teach .specclaw <change> log debrief "<summary>"
```

---

## Anti-patterns

| Anti-pattern | Why it fails | Instead |
|---|---|---|
| Generating docs before they're needed | Reads as thorough, functions as noise | Just-in-time or not at all |
| Explaining before checking the profile | Wastes a (c)/(d) user's session | Calibrate first |
| One design presented as the answer | Not a decision, just a habit | 2–4 options with costs |
| More than one next action per reply | Reintroduces "what now?" | Pick one |
| Teaching the tool instead of the concept | `SETEX` syntax is trivia | *Why* the TTL is jittered is the lesson |
| Walking the user through debugging | It's the agent's bug | Fix it; one line on the cause if instructive |
| "Does that make sense?" | Invites yes | Ask them to predict, decide, or explain |
| Answering your own gate question | Removes the decision | Ask, then stop |
| A brief for a (c)/(d) user | Signals the profile wasn't read | Skip to the decision |
