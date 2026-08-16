# Learning Plan — {{project}}

**Change:** {{change}} · **Generated:** {{date}} · **Depth:** {{depth}}

> **Start here → reply `{{first_action}}`.** What it opens with is in §6.

> The one document to keep open. Everything else is written at the step that needs it.
> Regenerate with `/specclaw:teach` after any level changes.

---

## 1. Your level map

| Technology | Level | Treatment |
|------------|-------|-----------|
| | | |

State the ratio: how many sit at (a)/(b), and therefore why briefs are one-per-task rather than a
reading pile. Note any level corrected by spot-check, and that a correction is not a mark against
them — an inflated level silently denies them teaching they'd have wanted.

---

## 2. Learn — concept briefs queued

One per technology rated **(a)** or **(b)**, delivered **immediately before** the task that needs it,
never in a batch up front. 3–4 minutes each: the problem it solves → mental model and where the
analogy breaks → 3–5 primitives → real numbers → the failure mode → what it costs.

| # | Brief | For task | Why you need it there | Status |
|---|-------|----------|----------------------|--------|
| | | | | ⬜ queued / ✅ given |

Cached to `knowledge/briefs/<topic>.md` as they're delivered.

---

## 3. Explain — decisions that are yours

Each is presented as 2–4 scored options with costs, one recommendation with a single deciding factor,
and what would change the recommender's mind. **You choose.** Your reason is recorded verbatim.

| # | Decision | Options | Blocks task | Status |
|---|----------|---------|-------------|--------|
| | | | | ⬜ open / ✅ ADR-000N |

---

## 4. PoC — where a throwaway experiment is faster than reading

Only where seeing a mechanism fail is genuinely quicker than being told about it. Not for every
technology — a PoC you don't need is the same waste as a brief you don't need.

| # | Experiment | Proves | Time | Status |
|---|-----------|--------|------|--------|
| | | | | ⬜ |

**The test for including one:** would watching this break change what you build? If not, skip it.

---

## 5. Implementation — the build sequence, interleaved

| Wave | Task | Level | Gate? | Your part |
|------|------|-------|-------|-----------|
| | | | | |

**Gate?** = the build pauses for a brief and a decision before starting. Triggered by any task
touching a technology rated (a) or (b), when `teach.gate_builds` is true.

**Your part** = decide / predict / observe. Never "type this code".

---

## 6. How to start

One concrete opening move — not a menu. Name the first task, why it's first, which briefs and
decisions it opens with, and the exact words to reply.

> **`{{first_action}}`** — {{first_task_title}}.
>
> It opens with {{briefs}}, then asks you {{decisions}}. Nothing gets written until you've decided.
>
> Reply **`{{first_action}}`**.

---

## 7. Predictions vs reality

The most useful table here. A wrong prediction marks exactly where your mental model diverges from
the system — which is the fastest thing to learn from.

| Task | You predicted | Measured | Gap explained by |
|------|--------------|----------|------------------|
| | | | |

---

## 8. Deliberately not learning this time

Naming what you're skipping is what keeps a plan finishable.

| Topic | Why skipped | Revisit when |
|-------|------------|--------------|
| | | |
