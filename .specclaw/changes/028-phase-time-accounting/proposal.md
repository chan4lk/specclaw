# Proposal: Phase time accounting — justify and explain long-running phases

**Created:** 2026-08-01
**Status:** 🟡 Draft

## Problem

Long specclaw phases (propose, plan, build, verify) are *acceptably* slow — the work is genuinely
large — but today they are **unaccountably** slow. There is no record of where the wall-clock went,
so nobody can tell a legitimate 40-minute build from a stalled one.

Concrete evidence from operator channels:

- **dstm-apps**: watchdog posted `⏳ still working (transcript active, 12 min since last reply)` and
  then `⚠️ agent stopped responding (no reply for 13 min). Tearing down`. The agent was very likely
  mid-work; the supervisor could not distinguish "thinking hard" from "hung", so it killed the run.
  Same pattern repeats in this repo's `watchdog-kills.jsonl`.
- **keyflow**: `🦞 Build Complete … Tasks: 11/11` arrived ~2h07m after `🦞 Build Started` with only
  two `✅ Bash` lines in between. The operator has no way to answer "why 2 hours?" — was it 11 slow
  tasks, one 90-minute test suite, or three silent retries?

What exists today is partial and not aggregated:

| Signal | Where | Gap |
|--------|-------|-----|
| `[run-long] Ns elapsed \| N log lines \| last: …` heartbeat | `bin/specclaw-run-long:273` (stderr) | Only for commands routed through run-long; never persisted into the change dir |
| `duration_s` in `.result` sidecar | `bin/specclaw-run-long:284-291` | Per-command, discarded after the caller reads pass/fail |
| `**When:** <UTC>` per error attempt | `bin/specclaw-log-error:118` | Only on failures; no start/end pairing |
| `Agent Runs` table with a `Duration` column | `templates/status.md:27-29` | Header exists, rows are **never written** by any script |
| `Last Updated` in STATUS.md | `bin/specclaw-update-status:144-167` | A clock stamp, not a duration |

So: no phase records its own start/end, no per-task durations land anywhere, the one template column
designed for this is dead, and the only live progress signal (`run-long` heartbeat) goes to stderr
and dies with the process.

Cost of the gap: (a) supervisors and operators kill healthy long runs; (b) nobody can point at the
actual bottleneck, so the same slow step gets paid for on every change; (c) "the build takes long"
is unfalsifiable, so it never gets optimised.

## Proposed Solution

Make every phase emit a **timing ledger** and a **live progress line**, then surface both. Timing is
already measured in places — this proposal captures it, attributes it, and reports it.

**1. `specclaw-timer` — one shared timing primitive (new `bin/` script).**

```
specclaw-timer start  .specclaw <change> <span-id> [--kind task|wave|phase|cmd] [--label "…"]
specclaw-timer stop   .specclaw <change> <span-id> [--status ok|fail|retry]
specclaw-timer report .specclaw <change> [--format md|json]
```

Appends one JSON line per span to `.specclaw/changes/<change>/timeline.jsonl`
(`{span_id, kind, label, parent, started_at, ended_at, duration_s, status, model?, attempt?}`).
Append-only JSONL so concurrent wave tasks cannot clobber each other, and a crashed run leaves an
open span that `report` renders as `⏱ still running` rather than losing the record.

**2. Instrument the phases that already have obvious boundaries.**

- `specclaw-build`: wrap each task and each wave in a span; record `model` and `attempt` (retry number).
- `specclaw-run-long`: on exit, fold its existing `duration_s` into the ledger as a `cmd` span instead
  of only writing the `.result` sidecar — this is where test/lint/build minutes actually go.
- `specclaw-verify`, `specclaw-loop`: one span per verify run / per loop turn (loop already writes
  `## Turn N` to `loop-log.md` with no timestamp — add one).
- `propose` / `plan`: single phase-level span each, opened by the skill, closed when the artifact is
  written. Cheap, and finally answers "how long does planning cost us?".

**3. Live justification line — "why this is taking long", not just "it is taking long".**

A `specclaw-progress` helper prints one line at each milestone and on a heartbeat interval:

```
⏱ build 18m32s · wave 2/4 · T5 in flight 6m11s (sonnet-5, attempt 2) · slowest so far: T3 test suite 9m04s
```

That line is the whole point: it names the **active step**, its **elapsed time**, and the **current
bottleneck**, so an operator or watchdog can judge liveness instead of guessing. Because it is real
stdout on a heartbeat, it also directly defuses the dstm-apps teardown: a pane that emits a progress
line every 60s is never "no reply for 13 min".

**4. Report it where people already look.**

- `timeline.md` (rendered from the ledger) written into the change dir alongside `errors.md` /
  `learnings.md`, so `specclaw-pr` already picks it up when it stages the change dir.
- Fill the dead `Agent Runs` table in `status.md` (task / agent / model / status / duration) from the
  ledger — the column exists, wire it up.
- A **Time accounting** section in the PR body: total wall clock, split by phase, top-3 slowest spans,
  retry count. This is the "justify it" deliverable — the PR itself explains its own cost.
- `STATUS.md` active-changes table gains an elapsed column so a stuck change is visible at a glance.

**5. Historical baselines (the payoff).** With ledgers accumulating per change, `specclaw-timer report
--baseline` reads previous changes' timelines to print a median for comparable spans, enabling
"T5 at 6m11s (median for test tasks: 2m40s)". Anomaly, not just duration. This is what turns timing
data into an actual explanation.

## Scope

### In Scope
- New `bin/specclaw-timer` (start/stop/report) writing `timeline.jsonl`, append-only, concurrency-safe.
- New `bin/specclaw-progress` heartbeat/milestone line formatter.
- Instrumentation of `specclaw-build` (task + wave spans, model, attempt), `specclaw-run-long`
  (fold existing `duration_s` into the ledger), `specclaw-verify`, `specclaw-loop` (per-turn span).
- Phase-level spans for `propose` and `plan` skills.
- `timeline.md` renderer; populate the existing `Agent Runs` table in `status.md`.
- **Time accounting** section in the PR body (`specclaw-pr` + `specclaw-azdo-pr` share the builder).
- Elapsed column in the `STATUS.md` active-changes table.
- `--baseline` median comparison across prior changes' timelines.
- Shellcheck-clean; new bats suite registered in CI (per PR #49 convention).

### Out of Scope
- Token/dollar cost accounting — durations only. (Natural follow-up; different data source.)
- Making anything actually faster. This proposal measures and explains; optimisation is a later change
  informed by the first ledgers.
- Changing watchdog/supervisor logic in the `mcd` bot — this only guarantees the pane keeps emitting a
  meaningful line, which is the part specclaw owns.
- Distributed tracing formats (OTLP), external dashboards, or a metrics backend. Local JSONL only.
- Retroactively reconstructing timings for already-archived changes.

## Impact

- **Files affected:** ~14 (estimated) — 2 new `bin/` scripts, ~6 instrumented scripts
  (`specclaw-build`, `specclaw-run-long`, `specclaw-verify`, `specclaw-loop`, `specclaw-update-status`,
  `specclaw-pr` + `specclaw-azdo-pr` body builder), 3 SKILL.md updates (propose, plan, build),
  `templates/status.md`, 1 new bats suite.
- **Complexity:** medium — the mechanism is simple (append a JSON line); the work is in threading spans
  through several long scripts without breaking existing exit-code contracts.
- **Risk:** low — additive and fail-open. Every timer call must be non-fatal (`|| true`): a broken
  ledger must never fail a build. Main real risk is noisy progress output; mitigate with a configurable
  heartbeat interval and a `build.progress: quiet|normal|verbose` switch.

## Open Questions

1. **Heartbeat interval** — reuse `run-long`'s 60s default everywhere, or slower (120s) for build waves?
   Trade-off is watchdog liveness vs. channel noise.
2. **Is `timeline.jsonl` committed, or is only the rendered `timeline.md`?** Committing raw JSONL gives
   reviewers exact numbers but adds churn to every PR. Lean: commit `timeline.md`, gitignore the JSONL.
3. **Baseline scope** — median over that project's archived changes only, or a global default table
   shipped with the plugin for fresh projects with no history?
4. **Do propose/plan spans need model attribution** to be useful, given planning is one long agent turn
   rather than a wrapped command?
5. Should exceeding a baseline by some factor (e.g. 3× median) **emit a warning line** — an early
   "this is abnormal, look at it" — or stay purely descriptive?
6. Where does the progress line go when specclaw runs headless under `/specclaw:loop` — stdout only, or
   also appended to `loop-log.md`?

---

**To proceed:** Review this proposal and approve to begin planning.
