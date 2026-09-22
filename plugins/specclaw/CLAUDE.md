# specclaw plugin — Claude Code instructions

## Project Context (`context.md`)

Every specclaw project can have a `.specclaw/context.md` — a living architecture document that captures project-level coding rules, patterns, style guides, and decisions. It is committed to the project repo (not gitignored) so it is shared across the team and reviewable in PRs.

**What it contains:** Architecture overview, coding style and conventions, key patterns, technology decisions, constraints (what not to do), and a log of recent decisions.

**How to create/edit it:** Use `/specclaw:context` — sub-commands: `show`, `add`, `edit`, `reset`.

**How it is used automatically:**
- `/specclaw:plan` reads `context.md` before generating spec, design, and tasks — decisions and constraints are applied throughout.
- `/specclaw:build` injects `context.md` into every coding agent's context payload via `specclaw-build-context`.
- `/specclaw:verify` checks the implementation against `context.md` rules in addition to spec acceptance criteria.
- `/specclaw:pr` and `/specclaw:pr-azdo` rewrite `context.md` after each merged change via `specclaw-update-context` — new decisions, patterns, and constraints from the change are merged in; stale information is replaced.

**Architecture-doc model:** `context.md` is always current. It is not an append log — it is rewritten to reflect the project's present state. Git history is the audit trail.

## Lifecycle

`propose` → `plan` → `build` → `verify` → `pr` → _(context auto-updated)_

Each phase has a corresponding skill. Run them in order. See individual SKILL.md files under `skills/` for details.

## Loop (autonomous build → verify → review)

When `loop.enabled: true` (the default), `/specclaw:loop` closes the build→verify→review cycle automatically instead of stopping at a FAIL/PARTIAL verdict. Each turn: run the four **local gates** (tasks-complete, test/lint/build commands, verify verdict, review BLOCK count) → if all green, done → otherwise `decide` whether to keep going or halt → feed the failing gates back as a structured **failure record** via `specclaw-build-context --failure-record` → a fix agent (`models.coding`) makes the *smallest diff to turn the failing gate green* → guard → commit → log the turn. Repeats until every gate is green or a guardrail halts.

**Guardrails (halt + escalate):** iteration cap (`max_iterations`), no-progress limit (`no_progress_limit` turns with no gate improvement), regression (a green gate goes red), and oscillation (a `failure_sig` repeats). On halt, `specclaw-loop escalate` commits partial work with the specclaw prefix, keeps the worktree intact, finalizes `loop-log.md`, and notifies the operator with the halt reason + current gate status.

**Reward-hack guard:** after each fix turn, changed files are intersected with `loop.test_paths`. On a hit the guard reverts the test edits (`guard_action: revert-tests`) or the whole turn (`revert-turn`), logs the trip, and marks the turn a non-progress failure — tests always execute from committed HEAD, never same-turn agent edits.

**CI outer loop:** when `loop.ci_gate: true`, after the PR branch is pushed the loop polls CI (`specclaw-loop ci-poll` — `gh pr checks` for GitHub, `az pipelines runs` for Azure) and iterates fixes until green, or `ci_max_iterations` / `ci_timeout_seconds` halts. Polling is **in-session only** (no MCD / background messaging); "no checks after grace" counts as green with a warning.

**Config** — the `loop:` block (seeded default-on by `specclaw-init`): `enabled`, `max_iterations` (5), `no_progress_limit` (2), `guard_action` (`revert-tests`), `test_paths` ([]), `ci_gate` (false), `ci_max_iterations` (3), `ci_timeout_seconds` (1200). Set `loop.enabled: false` for the single-pass path — build/verify/pr behave exactly as their SKILL.md documents, no loop, no extra files.

## Party mode (an adversarial panel inside `propose`)

When `party.enabled: true`, `/specclaw:propose` inserts one step between writing `proposal.md` and
presenting it: a panel of role-specialised subagents (`party-po`, `party-architect`, `party-ba`,
`party-visionary`, `party-security`) critiques the proposal from non-overlapping angles, rebuts each
other in a second round, and `specclaw-party` tallies a verdict into
`changes/<change>/party-report.md`.

**It is a step, not a phase.** There is no `party` rank in
`proposal spec design tasks build verify pr archived`, `specclaw-set-phase` is never called for it,
and `state.json` never mentions it. A change that ran a panel and one that did not are the same shape
on disk apart from one extra report. A phase would have meant a lifecycle rank that most changes
skip, and a `validate-change` prerequisite for a thing whose entire contract is that it is optional
and advisory: **the panel informs, the operator decides.** `CHANGES_REQUESTED` blocks nothing unless
`party.block: true`, which ships `false`.

### A model judges; a script decides

| Layer | Owner | Party-mode instance |
|-------|-------|---------------------|
| Judgement | model | `party-classifier` picks a depth tier; the panelists write findings |
| Arithmetic / state | bash | `specclaw-party` resolves seats, clamps them, tallies the verdict, writes `panel.json` |

The line is drawn where re-running the same input must give the same answer. "Is this proposal deep?"
and "is this objection worth raising?" have no closed form — every proxy for them (word counts,
keyword lists) was gameable by the same model that wrote the proposal, so they are irreducibly model
work. Seat resolution, tail-order clamping, the `≥1 BLOCK` / `≥2 roles WARN` rule and the BLOCK count
have exactly one correct answer, and arithmetic performed by a model is arithmetic that drifts
between two runs on identical input. This is the same split as `specclaw-loop` (the controller
evaluates the gates; the fix agent writes the diff) and `specclaw-parse-tasks --count`.

Concretely: `tally_counts` in `bin/specclaw-party` is the only place the verdict rule is written
down, no prompt anywhere asks a model what the verdict is, and `skills/propose/SKILL.md` reads the
printed token — *"never recompute or second-guess it"*. `tally` and `report` also share one findings
scanner, so the two can never disagree about what a finding is.

Bash cannot spawn subagents, so the handshake runs the other way: `panel` prints the classifier
prompt and exits **10**, meaning "I need a model turn"; the skill spawns `party-classifier`, writes
its answer to `party/classification.json`, and re-runs the same command. Lifted from
`skills/build/SKILL.md` and `specclaw-build synth-agent`.

### The panel is sized to the proposal

`party-classifier` (`haiku`, `tools: [Read]`) returns a tier and domain flags; `panel` turns that
into a roster with no further model involvement:

| Tier | Seats |
|------|-------|
| `thin` | `party-po`, `party-architect` |
| `standard` | `party-po`, `party-architect`, `party-ba` |
| `deep` | `party-po`, `party-architect`, `party-ba`, `party-visionary` |
| any tier | `+ party-security` when the tier is `deep` **or** `security ∈ domains` |

The domain match is **case-insensitive**. `domains` is model-written, and a model asked for
`security` will eventually answer `Security`; an exact match would drop the specialist on that
spelling alone and leave a roster that still reads like a working thin panel.

Then: union `party.always`, drop seats with no `agents/<seat>.md` (warn, record it), and clamp to
`[min_seats, max_seats]` — dropping from the **tail** of the tier order
`po, architect, ba, security, visionary`, so the Visionary goes first and PO/Architect last, and
every drop is named in `panel.json`.

**Security sits ahead of the Visionary on purpose.** It is the one seat that is never on the roster
by default — it arrives only because the classifier flagged a trust boundary or because the tier is
`deep` — so a ceiling that drops it first is discarding the seat something specifically asked for,
on the panel that asked for it. The Visionary's mandate (does this compound?) survives being deferred
to the next review; a fail-open in the token path does not. The first cut of this change ordered them
the other way and its test asserted only "Visionary before Architect", which held under both orders
and so pinned neither; the suite now names every drop in sequence.

The same array orders the `min_seats` growth loop, so a panel grown to a floor fills in the order it
would empty. The roster is cached on a `cksum`
of `proposal.md`, so a retry cannot draw a different panel — and a different bill — from an unedited
proposal; an edited one re-classifies, and `--repanel` forces it.

Two overrides skip the classifier spawn entirely: `--panel <tier>` (`tier_source: override`) and
`panel_mode: fixed`, which takes `party.panel` verbatim (`tier_source: fixed`). **`fixed` with an
empty or absent `party.panel` warns and names the key**, because the roster it would otherwise build
in silence is the two-seat head of the tier order — indistinguishable from a deliberate `thin`
classification, so a config typo would read back as a decision nobody made.

### The fallback is `standard`, and never `thin`

A classifier that errors, exits non-zero, emits unparseable output, or names an unknown tier yields
tier `standard`, `tier_source: fallback`, a warning on stderr, and **exit 0**.

Never `thin`, because the failure mode of a cheap classifier is a *silent downgrade*, and a two-seat
panel looks exactly like a working one. Erring upward costs a couple of spawns; erring downward costs
the review itself and leaves a green-looking report on a proposal nobody actually argued with — the
one failure that would never be noticed, because its output is indistinguishable from success. So it
is made visible three ways: stderr, `tier_source` in `panel.json`, and the `**Tier:**` line of the
report.

That matters more than an error path usually would, because **the fallback is the automatic behaviour
of any caller that does not implement the exit-10 handshake.** A mis-wired caller therefore stamps
`"tier_source": "fallback"` into every `panel.json` it writes, rather than into none of them.

**Config** — the `party:` block (seeded by `specclaw-init`, shipped **inert**): `enabled` (true),
`default` (false — ask once, quoting the roster and the per-model spawn count, before spending),
`on_loop_halt` (false), `rounds` (2; `1` skips rebuttal and halves the bill), `block` (false),
`panel_mode` (`dynamic`), `panel` (the roster `fixed` uses), `always` ([]), `min_seats` (2),
`max_seats` (6), and `models` (per-seat; a seat left out falls through to its charter's own `model:`).
`default`, `block` and `on_loop_halt` all ship `false`, so upgrading changes no existing `propose`
run — the same one-release rollout `workflow.code_review_block` took. `enabled: false` is a total
off switch: no prompt, no files, no spawns.

## Party config reads: `party_val` is the only reader of the `party:` block

`yaml_val` (`bin/specclaw-loop:87-102`) reduces a dotted path to its **last component** —
`field="${key##*.}"` — and then greps the whole file for the first `<field>:` line. `config.yaml`
already carries a top-level `models:` block. So:

```
yaml_val "$config" party.models           # greps `models:`     → the top-level block
yaml_val "$config" party.enabled          # greps `enabled:`    → build.dynamic_agents.enabled — false
yaml_val "$config" party.models.party-po  # greps `party-po:`   → right answer, by luck alone
```

Not an error, not empty: **the wrong block, silently, with a plausible value in it.** The second line
is the shipped config as it stands — `party.enabled` reads `false` off a block seventy lines above
the one asked for, so party mode would be off while the config plainly says `true`. The third line is
the more dangerous one, because it is *correct today*: nothing above `party:` currently has a
`party-po:` key, so the whole-file grep lands on the right line and every test passes — until some
future block gains a key of that name, and the panel quietly starts spawning on a model nobody chose.

`bin/specclaw-party` therefore ships `party_val` (and `party_list` for the `[a, b]`, indented `- a`
and **column-0 `- a`** list forms — the last is what `yq` and `ruamel` emit by default, and reading
it as an empty list silently disabled `party.always`, the operator's escape hatch, on the run that
needed it), modelled on `da_val` (`bin/specclaw-build:557-574`): seek to the column-0 `party:` line,
read only until the next column-0 key, and resolve the dotted path inside **that window**. **No party
config value may be read any other way** — not with `yaml_val`, not with a `grep` in a SKILL.md, not
with a one-off `sed`.

**A rule needs a mechanism, or it is a comment.** That invariant first shipped alongside its own
first violation: `skills/propose/SKILL.md` was told to read `party.enabled` and given nothing to read
it with, so the only available reading was a whole-file one — which returns `false` off
`build.dynamic_agents.enabled`, seventy lines above the key asked for, producing a `propose` run
indistinguishable from party mode being correctly switched off. The mechanism is:

```
specclaw-party get <specclaw_dir> <key> [--default <value>]
```

a thin wrapper on `party_val`, and on `party_list` for the closed set of list-valued keys
(`panel`, `always`), which print **one item per line** whichever YAML form the config used. Every
other key prints a single line; an absent key prints nothing and exits 0, so `--default` is how a
caller distinguishes unset from set-but-empty. Argument errors exit 2 — never a silent empty answer.
Any skill or script outside `specclaw-party` reads party config through `get` or not at all.

`run-party-tests.sh` pins this, and the fixture is the interesting half: its `config.yaml` carries
both blocks, the top-level `models:` block carries decoy `party-visionary:` / `party-po:` keys, and a
decoy block above `party:` carries every scalar key the script reads. Without those decoys a
regression to `yaml_val` passes by luck — nothing in the fixture would collide — while the shipped
`config.yaml` silently reads the wrong section. The decoys *are* the test; do not tidy them away.

## Session bootstrap (the `SessionStart` hook)

`hooks/hooks.json` registers `hooks/session-start` on `startup|clear|compact`. It injects
`skills/using-specclaw/SKILL.md` — the intent router — plus a live state block from
`specclaw-bootstrap-snapshot`, as `hookSpecificOutput.additionalContext`.

**This is what makes the skills fire.** Without it specclaw is ~30 skill descriptions competing with
every other installed plugin's, and the model knows nothing about what is already in flight in the
project.

Four rules the hook obeys, each because of a specific failure:

1. **Inert outside specclaw projects.** No `./.specclaw/config.yaml` → emits nothing, exits 0. The
   gate is the *config file*, not the `.specclaw/` directory: a stray directory turns up in repos
   that once had a change dir committed, in vendored copies, and in this plugin's own fixtures.
2. **Never breaks a session.** Every path exits 0, and there are exactly three outcomes: nothing,
   router + state, or router alone. The snapshot is captured into a variable *before* anything is
   printed, because a partial JSON document is worse than no document — the harness rejects it and
   the session opens on a parse error.
3. **Block-scoped config reads.** `bootstrap.enabled` is read from the column-0 `bootstrap:` block
   only. A whole-file `grep enabled:` finds `build.dynamic_agents.enabled`, `loop.enabled`,
   `party.enabled` or `notifications.enabled` — four keys of that name sit above `bootstrap:` — so
   it would switch the bootstrap on or off by whichever block came first, silently, while the config
   plainly said otherwise. Same defect and same fix as `party_val`.
4. **`printf`, never a heredoc.** superpowers hit a bash 5.3 heredoc hang building exactly this
   payload (their issue #571).

**The router forces exactly one route.** `/specclaw:propose` for new work in the codebase is a MUST,
in superpowers' own register, because it is the only route with no recovery path: a change that
begins without a proposal has no change dir, and nothing downstream can create one retroactively.
Every other verb is a deterministic table row and **may be declined**. Applying forcing language to
every verb would make the router a mood rather than a table.

**The state block is the part superpowers does not have, and the part that makes routing
controlled.** "The tests are failing" routes to `/specclaw:debug` mid-build and to
`/specclaw:propose` on a clean tree. Without the recorded phase in context the model cannot tell
those apart. `specclaw-bootstrap-snapshot` reads `state.json`, `tasks.md` (via
`specclaw-parse-tasks --count`, the only counter) and `proposal.md` — **from disk, never a model
turn** — and writes nothing at all.

**Config** — the `bootstrap:` block seeded by `specclaw-init`: `enabled` (true), `snapshot` (true),
`max_lines` (15). The injected payload is capped at 8000 bytes and the cap is asserted in
`run-bootstrap-hook-tests.sh`; it is paid for on every session start, clear and compact.

**Hooks load from the installed plugin, not from the repo checkout.** A working copy that is ahead of
the installed version still runs the old hook, and the symptom is silence rather than an error —
`specclaw-check-update` says so in its upgrade notice.

## Scripts

All executable scripts live in `bin/`. Key ones:

| Script | Purpose |
|--------|---------|
| `specclaw-ensure-init` | Idempotently init `.specclaw/` |
| `specclaw-build-context` | Build coding agent payload (includes context.md; `--failure-record`/`--reflection` for loop remediation) |
| `specclaw-loop` | Autonomous loop controller: `init` / `gates` / `decide` / `guard-tests` / `log-turn` / `escalate` / `ci-poll` / `done` |
| `specclaw-update-context` | Output LLM prompt to rewrite context.md post-merge |
| `specclaw-run-long` | Run a long command detached: heartbeats to stderr, capped tail to stdout, full log + HEAD-stamped sidecar on disk; `--reuse` skips a re-run when HEAD matches and the tree is clean |
| `specclaw-set-phase` | **The only phase writer** — see below |
| `specclaw-reconcile` | Detect (and `--fix`) drift between `state.json` and observed reality |
| `specclaw-update-status` | Regenerate `.specclaw/STATUS.md` dashboard (renders the recorded phase; resolves PR state on the recorded branch) |
| `specclaw-status-row` | Upsert one row of a change's `status.md` Progress table (awk — the table's pipes make `sed` unsafe) |
| `specclaw-next-change-number` | Print the next change number (`001`), derived from disk on every call — see below |
| `specclaw-renumber-changes` | Backfill ordinals onto unnumbered change folders (dry run unless `--apply`) |
| `specclaw-gh-sync` | GitHub Issues sync |
| `specclaw-pr` | Create GitHub PR (enforces test policy, triggers context update) |
| `specclaw-validate-change` | Check phase prerequisites |
| `specclaw-parse-tasks` | Parse `tasks.md` → JSON; **the only task counter** (`--count`) — see below |
| `specclaw-bootstrap-snapshot` | The live state block the `SessionStart` hook injects: one row per active change and pending proposal, from `state.json` / `tasks.md` / `proposal.md`. Reads only — writes nothing anywhere, spawns no model, exits 0 on every path |
| `specclaw-timer` | The timing ledger: `start` / `stop` / `report` (`--baseline`, `--write`) / `agent-runs` / `active`. Append-only JSONL, no locking, **exits 0 on every path but a usage error** |
| `specclaw-progress` | One line naming the active step, its elapsed time and the current bottleneck — what lets an operator or a watchdog judge liveness instead of guessing |
| `specclaw-check-staged` | The staged-files gate: four buckets, `--json`, `--strict`. Exit 1 on a BLOCK, 2 on a usage error — a caller must be able to tell "this PR is wrong" from "you called me wrong" |
| `specclaw-build` | Build orchestration: `setup` / `commit` / `finalize` / `worktree-path` / `synth-agent` / `check-report` (**the evidence gate on `done`**) / `review-package` (prepare one task's diff for a task-scoped review; read-only w.r.t. git) |
| `specclaw-set-size` | The one-way size ratchet (`spike → bounded → architectural`). Refuses downgrades and no-ops **by name**; does not write `state.json` itself — it re-records the current phase through `specclaw-set-phase`, which stays the only writer |
| `specclaw-party` | Adversarial proposal panel: `panel` (resolve the roster) / `tally` (compute the verdict) / `report` (assemble `party-report.md`) / `get` (**the only reader of the `party:` block**) — see below |
| `specclaw-bf-status` | Per-**phase** brownfield dashboard to stdout: one row per `bf-*` phase, the open items holding each back, and the next command. `--next` prints the same computation as the compact guidance block every lifecycle `bf-*` skill appends to its own summary — the next human **action**, the next **command**, and a short attention list. **This is the single source of the `bf-*` lifecycle ordering**; no skill may work out its own next phase. Writes nothing in either mode — no file, no cache, no archive entry. jq optional. Complements `specclaw-bf-rebuild-collect module-status`, which is the per-**module** view and *is* a written artifact |
| `specclaw-bf-bootstrap` | Target-foundation stage: `collect` (validate + resolve the required decisions) / `gate` (foundation-only boundary) / `smoke` / `record` / `foundation-check` (the gate `/specclaw:propose` reads) / `not-applicable` |
| `specclaw-bf-clarify` | Clarify engine: `collect` / `render` (extract mode) / `resolve-collect` / `resolve-render` (`--resolve`) / `options-pack-collect` / `options-pack-render` (`--options-pack` — the client decision paper; bash owns every DECIDED/UNDECIDED/NOT-APPLICABLE verdict, the header counts and the Client-decision lines) |
| `specclaw-bf-blueprint` | Target blueprint: `collect` (module roster + structural legacy inventory + decision status + the bash-computed `Blueprint status:` line) / `render` (three refusal gates: uncited mapping row, citation to a non-existent id, missing or invented module section) |
| `specclaw-bf-quality-collect` | Code-quality measurement: `collect` (probe scc/lizard/jscpd, enumerate, join files to `MOD-###` via the map's own Evidence citations, classify against `config.yaml`'s `quality:` thresholds, register `QI-###`, snapshot) / `compare` (per-module per-metric deltas, `NOT-COMPARABLE` for one-sided dimensions, and the `--gate` verdict). Bash owns every status, severity, rollup and verdict; the agent only narrates. Advisory except `compare --gate` |

## Task counting: `specclaw-parse-tasks --count` is the only counter

`specclaw-parse-tasks --count <tasks.md>` prints `<done> <total> <failed>` — three integers, no
`jq` needed. `reconcile`, `build`, `update-status`, and `validate-change` all read it. **Nothing may
count tasks with `grep`**, and `run-parser-tests.sh` fails if any `bin/` script tries.

A task is a top-level checkbox line carrying a backtick-wrapped `` `T<n>` `` id, **outside** any
```` ``` ```` fence. Both halves of that rule matter, and fences are the half that kept getting
dropped: `tasks.md` ships a template snippet containing `` - [ ] `T<n>` — <title> ``, and any
example with a numeric id — `` `T9` `` — read as a real task. The fence rule was written four
times; `validate-change` had it, three callers used `grep -c '^- \['`, and `parse-tasks` itself,
which every other reader is built on, had none.

The counting drift was the visible half: a finished change rendered `5/6 tasks (83%)` on the
dashboard forever. The expensive half was `specclaw-loop` gate 1, which reads `--status pending` —
a fenced `` - [ ] `T9` `` surfaced as an incomplete task that does not exist and cannot be
completed, so the loop spent every iteration failing to close it.

**A bare `- [x] T1` is not a task.** `reconcile`, `build`, and `update-status` used to count it
because `grep` cannot tell an id from prose; they no longer do. Since dropping a real task is worse
than counting a fake one, `--count` writes one summary line to stderr naming how many checkboxes it
skipped, and **no caller suppresses it** — a file of un-backticked checkboxes reads `0 0 0` out
loud, never quietly.

## Phase state: `specclaw-set-phase` is the only writer

Each change's phase lives in `changes/<change>/state.json`. **Nothing else may write it** — not a
script, not a skill, not the model editing `status.md` prose. Every phase transition goes through:

```
specclaw-set-phase .specclaw <change> <phase> <status> [--note S] [--url U] [--verdict V] \
                   [--branch B] [--tasks done/total/failed] [--force]
```

Phases rank `proposal spec design tasks build verify pr archived`. A transition to a lower rank is
refused unless `--force`; equal rank is allowed (re-running verify, updating a PR URL). The write is
atomic (temp file → parse check → `mv`), and the human-readable `status.md` row is delegated to
`specclaw-status-row` so the two can never disagree.

**Why it matters:** before this, build, verify, both PR scripts, and three SKILL.md files each
rewrote `status.md` their own way, and `STATUS.md` re-derived the phase by counting checkboxes. Any
one of them could disagree with the others, and regularly did.

`specclaw-update-status` renders the recorded phase and resolves PR state on the **recorded** branch
rather than guessing `${branch_prefix}${change}`. A change with no `state.json` still falls through
to checkbox inference with a warning, so pre-existing changes keep working untouched.

`specclaw-reconcile .specclaw [<change>] [--fix]` audits `state.json` against `tasks.md` markers,
`verify-report.md`, and `gh pr view` on the recorded branch. It exits non-zero on drift. A `gh`
failure is `unknown`, never `no PR` — `--fix` skips unknowns and downgrades and reports how many
findings it declined, so exit 0 can never be misread as clean.

## Change numbering: the directory name *is* the number

Change folders are `NNN-<slug>` — `001-init-repo` — assigned once by
`specclaw-next-change-number` at propose time and carried through archival unchanged, so
`ls changes/` reads chronologically rather than alphabetically.

**Three digits, not two.** At this repo's rate two digits exhaust inside a year, and the overflow
fails *silently*: `100-foo` sorts before `99-foo` lexically, breaking the exact ordering the
numbering exists to provide. One extra character removes the failure mode outright.

**Derived, never stored.** The number is the maximum found on disk plus one, recomputed on every
call. There is deliberately no counter file — a counter is a second copy of a fact the directory
name already holds, and a second copy is a thing that drifts. Gaps are therefore permanent: deleting
`002` retires that number rather than reissuing it, so a number in a branch name or a commit message
always means the same change.

**What counts as numbered.** A folder qualifies only if its name matches `^[0-9]+-` and **not**
`^[0-9]{4}-[0-9]{2}-[0-9]{2}`. The second clause excludes the legacy `YYYY-MM-DD-` archive prefix,
whose leading digit run is a *year*, not an ordinal. Without it, this repo's 26 archived folders put
the maximum at 2026 and the next proposal would have been `2027-<slug>` — poisoning the sequence
permanently. The exclusion is narrow by design, firing only on the full date shape, so a genuine
ordinal like `2026-some-slug` still counts.

**Backfill is opt-in.** Upgrading specclaw renames nothing. `specclaw-renumber-changes` is a dry run
by default and needs `--apply` to move anything; `--force` renumbers from `001` when folders are
already numbered, which is also the documented recovery from an interrupted run. Mixed numbered and
unnumbered folders is a supported steady state, not an error — a repo that never backfills keeps
working indefinitely.

**Archived folders keep their number and gain no date prefix.** The old `YYYY-MM-DD-` prefix was the
*archive* date, not the change's, and a single bulk run here stamped 24 folders with one identical
date — ordering by it was actively misleading. The archive date lives in `state.json`, where it is
accurate.

## Tests

Suites live in `tests/`, are bash + coreutils only (no jq in the suites themselves; `run-parser-tests.sh` shells out to it), and **every one must be registered in `.github/workflows/ci.yml`** — an unregistered suite silently never runs, which has happened twice.

| Suite | Covers |
|-------|--------|
| `run-parser-tests.sh` | tasks/AC/changed-files parsing (needs `jq` installed) |
| `run-memory-parallelism-tests.sh` | memory-aware build concurrency, browser slot pool |
| `run-long-orchestration-tests.sh` | `run-long`, the e2e tier, `browser-lock wrap`, PR-aware status |
| `run-synth-agent-tests.sh` | dynamically synthesized build subagents |
| `run-shellcheck-gate-tests.sh` | the shellcheck gate itself |
| `run-replay-classification-tests.sh` | field-path language, record-time validation, divergence classification, verdict order |
| `run-stub-registry-tests.sh` | module bypass: `bypass-check` classification, the declared `BUILT:` signal, registry refusals, and that stub taint changes no verdict or exit code |
| `run-bootstrap-gate-tests.sh` | the target-foundation stage: the propose gate (inert / not-ready / naming its command), the loud stop on an undecided required `SQ-###`, the foundation-only gate refusing a BL capability, `record`'s refusals, re-run behaviour, and that the gate fails closed |
| `run-item-split-tests.sh` | item splits: the DR partition and layer-removal guards, the `IS-###` record's fields, `ACTIVE → READY-TO-RESUME → COMPLETE` and who flips each, marker rendering/clearing, resume-not-restart, and that PARTIAL changes no verdict or exit code |
| `run-blueprint-tests.sh` | the client options pack and the target blueprint: the three-way decision-status computation, empty-field integrity in the scan, the zero-pending clean state, the options-pack draft refusals, the blueprint's missing-input stops, unconfirmed-map-is-a-WARN-not-a-stop, and all three render gates |
| `run-cs-body-parser-tests.sh` | validation-routine body parsing per language: the C# `{`/`}` parser, a golden byte-comparison proving the Pascal `begin`/`end;` path is untouched, and a mixed `.pas` + `.cs` run (needs `jq`) |
| `run-bf-status-tests.sh` | the brownfield phase dashboard and the `--next` guidance block, including no-write guarantees, per-target replay verdict handling, action-vs-command guidance, post-bootstrap recommendation, replay FAIL attention, and lifecycle-ordering checks |
| `run-baseline-collect-tests.sh` | `specclaw-bf-baseline collect`'s module-map co-ownership reciprocity: a `DR-###` annotated `(co-owned with MOD-###)` on only one module's line still lands in both modules' `rules[]`, nearest-id-on-the-same-line pairing, and no duplicate when both sides already repeat the id |
| `run-bf-e2e-run-tests.sh` | `specclaw-bf-e2e-run`: executing bf-e2e's generated suite and patching `e2e-report.md`'s Execution Results and Artifacts anchors — never fabricating a count or a file, byte-fidelity outside both anchored regions, a failed install skipping the test command entirely, parsing across Playwright/Jest/pytest-, Mocha-, and dotnet-test-style summary lines, leaving an already-running service alone, sequential service startup gated on readiness, tearing down a service that never became ready without leaking its process, collecting on-failure screenshots/video into `.specclaw/e2e/artifacts/` (typed by extension, folder structure preserved, "None" when nothing was captured), and mechanically rendering `e2e-report.html` from the finished markdown for both technical and non-technical readers — a plain-language verdict banner (color/icon/one-sentence summary) and a CSS donut chart whose slices match the real Pass/Fail/Skipped split, stat cards matching the markdown's own numbers, a plain-language Test Scenarios list grouped by `### Module:` heading (a business-feature grouping, never a raw file path — a scenario with no module heading above it still renders, folded into one implicit group, rather than being dropped), with the individual checks each scenario makes as sub-bullets underneath and its `Evidence:`/`Test file:` lines styled as de-emphasized metadata, so the scenario count and check count in its badge (counted straight from the raw markdown's top-level vs. indented `- ` bullets) explain why an aggregate pass count is larger than the number of named scenarios — positioned ahead of the fold, a lone "None" Gaps bullet counting as zero, developer-only detail (stack, run commands) collapsed behind one `<details>` block, a not-executed run degrading to placeholders rather than errors, and `$(...)`/backticks/`<script>` in agent-authored content staying inert text — never evaluated by the shell, never breaking HTML escaping) |
| `run-quality-tests.sh` | the code-quality collector: per-language coverage, `NOT-MEASURED` reason precedence, threshold bands, `QI-###` permanence, compare classification, gate exit codes, module joins, and rebuild-plan rendering checks |
| `run-status-row-tests.sh` | `status-row` upserts, and the two sed defects it replaced |
| `run-phase-state-tests.sh` | `set-phase` transitions and `reconcile` drift detection |
| `run-loop-gate-tests.sh` | `loop gates` report readers — BLOCK counting and verdict extraction |
| `run-change-numbering-tests.sh` | `next-change-number` derivation, `renumber-changes` plan/refusals/backfill |
| `run-party-tests.sh` | party seat resolution and clamping, the fail-loud fallback, the panel cache, the verdict tally, the report grammar, and the `party_val` config-collision regression |
| `run-debug-protocol-tests.sh` | the investigation record's grammar and its two refusals, the `architecture-question` halt and its four counting rules, halt-reason slugs, the fix agent's root-cause payload, and cause-based pattern clustering |
| `run-change-size-tests.sh` | the size field's round-trip and carry-over, the per-size validation matrix (including the no-size row), every ratchet refusal, the status.md row, the re-required `design.md`, and the dashboard glyph |
| `run-bootstrap-hook-tests.sh` | the session-start hook: both silent paths, JSON validity, the router and state content, the block-scoped `bootstrap.enabled` read against decoy keys, the byte cap, `max_lines`, and the snapshot's no-write guarantee |
| `run-description-lint-tests.sh` | **the lint itself**, not a test of it — `LEN` / `TRIGGER` / `NARRATION` over every `skills/*/SKILL.md`, against `description-lint-baseline.txt` |
| `run-lint-meta-tests.sh` | the lint's rules, pinned against synthetic skills in a temp tree so they do not depend on what the real descriptions say today; plus the trigger fixture's shape and the runner's opt-in and fail-loud behaviour |
| `run-trigger-tests.sh` | **opt-in, costs API calls** (`SPECCLAW_TRIGGER_EVALS=1`) — does an utterance reach the right verb. Nightly in `trigger-evals.yml`, never on push |
| `run-task-review-tests.sh` | `check-report`'s three verdicts and the fenced-footer decoy, the last-footer-wins rule, `review-package`'s contents and its git-cleanliness, and the prompt/template/agent wiring |
| `run-timing-tests.sh` | the span round-trip, eight concurrent writers losing nothing, the unclosed span, both report formats, `agent-runs`, enclosing spans not double-counting, the baseline present and absent, the anomaly threshold either side, `enabled: false`, a corrupt ledger line, and `run-long` with and without `--change` |
| `run-staged-files-tests.sh` | the four buckets against real git repos: the missing artifact, the undeclared ripple under default and `--strict`, the junk sweep, both escape hatches, the size-aware artifact set, exit-code separation, the loop's scoped add against an untracked junk file, and that no PR-creation command lives in build |
`shellcheck-gate.sh` fails CI on any shellcheck finding absent from `shellcheck-baseline.txt` (pairs of `<path> <SCxxxx>`, no line numbers, so unrelated edits do not churn it). Fix a new finding or add a targeted `# shellcheck disable=SCxxxx` with a rationale — never silence one by appending to the baseline. It skips with exit 0 when shellcheck is not installed, so the suite still runs locally.

## Phase time accounting: the ledger is append-only

Long phases were acceptably slow and **unaccountably** slow. Nothing recorded where the wall-clock
went, so nobody could tell a legitimate 40-minute build from a stalled one — supervisors killed
healthy runs, and "the build takes long" was unfalsifiable and therefore never got fixed.

`specclaw-timer start|stop|report|agent-runs|active` writes `changes/<change>/timeline.jsonl`: **two
events per span, never a rewrite**. Three consequences, all of them the point:

- Build runs up to `parallel_tasks` agents at once. A ledger each of them read, modified and wrote
  back would lose spans; a single `>>` line does not.
- A crashed run leaves an **open span**, rendered `⏱ still running`. A ledger that dropped it
  instead would make a hang indistinguishable from a step that never started — the exact question
  this exists to answer.
- Nothing needs locking, so a timer call is one `date` and one `>>`.

**Every path exits 0** except a usage error. A build that failed because its *stopwatch* broke would
be strictly worse than the unaccountability being fixed, and the call sites are inside the longest
scripts in the plugin. Every call site ends in `|| true`, and `timing.enabled: false` short-circuits
before any file is touched.

`phase` and `wave` spans **do not** contribute to the total: they enclose the task and cmd spans
inside them, and counting both reports a build as longer than it was.

`specclaw-progress` is the deliverable, not the ledger:

```
⏱ build 18m32s · T5 in flight 6m11s (sonnet-5, attempt 2) · slowest so far: T3 9m04s
```

A watchdog tore down a healthy run with *"no reply for 13 min"* because it could not tell "thinking
hard" from "hung". A pane emitting this every `timing.heartbeat_seconds` is never silent that long,
and it names the **active step** and the **current bottleneck**, so the judgement it enables is
"this is normal" or "this is not".

**Baselines are project-local, and an absent one says so.** `report --baseline` takes the median for
the same `kind`+`label` across that project's own archived changes. A table shipped with the plugin
would be a median of somebody else's hardware, test suite and network — unfalsifiable. A project with
no history prints the report *and* a line saying there is no baseline, because a silently missing
column reads as "nothing was anomalous". The `⚠ N.N× median` marker is **descriptive only**: a slow
run is not a failed one, and a timing feature that can fail a build is one people switch off.

`timeline.md` (the render) is committed and quoted into the PR body's **Time accounting** section;
`timeline.jsonl` is gitignored by `specclaw-init`.

## The staged-files gate: which files, never what is in them

PRs shipped the wrong file set in **both** directions, silently. Planning artifacts went missing —
reported three separate times on one change, because `validate-change` checks that artifacts exist
*on disk* and nothing asked whether they were *committed*. And junk got swept in: `specclaw-loop`'s
escalation ran `git add -A`, and this repo's own tree has carried `.session-id.rotated-*` files, a
`watchdog-kills.jsonl` and an untracked `GOALS.md`.

**Layer 1 — `specclaw-check-staged`.** Deterministic, no model, no network. Four buckets:

| Bucket | Rule | Verdict |
|---|---|---|
| `required-missing` | a mandatory artifact absent from the branch diff | **BLOCK** |
| `declared` | declared by a task's `Files:`, or inside the change dir | ok |
| `undeclared` | changed on the branch, declared by no task | WARN |
| `suspicious` | matches a junk pattern | **BLOCK** |

The artifact set is **size-aware** (change 036): `design.md` only for architectural, and a spike is
measured against `findings.md` rather than a verify report.

**`undeclared` never blocks on its own**, and that is a decision about false positives.
`tasks.md` file lists are a scope *signal*, not a contract — tasks under-declare routinely, and a
barrel export updated for a new module is a legitimate ripple that will never appear in one. **A gate
that blocks a correct PR is worse than the silent failure it replaces.** `--strict` exists for a CI
caller that wants no judgement calls, and it is opt-in.

**Layer 2 — `staged-files-auditor`.** The model seat for the one question a script cannot answer: is
this undeclared file a ripple or scope creep? Spawned **only when there is something to judge** — a
non-empty `required-missing`/`suspicious`, or more than `pr.audit_undeclared_threshold` undeclared
paths. A reviewer convened over a clean file list is a bill with no finding attached. Same report
shape, verdict vocabulary and config gate as `code-reviewer`: a reviewer for *content* already
existed; this is the reviewer for *file set*.

**Layer 3 — closing the bypass.** A gate is worthless if `gh pr create` can be hand-rolled.
`specclaw-build` creates no PR and its summary names none — that is pinned by a test, not just
documented. And the loop's escalation is now a **scoped add**: the change dir, the paths `tasks.md`
declares, and `git add -u` for tracked modifications; everything else is **named in the escalation
note** as left in the working tree. An unparseable `tasks.md` does not restore `-A` — losing an
untracked scratch file is recoverable, a merged branch carrying the filesystem is not.

**Config** — `workflow.staged_files_audit` (true), `workflow.staged_files_block` (**false**, the
same one-release rollout `code_review_block` took), `pr.allowed_extra_paths` (wins over every rule,
including junk), `pr.junk_patterns` (project additions to the shipped defaults), and
`pr.audit_undeclared_threshold` (3). The report names `.gitignore` as the real fix for a recurring
junk pattern, because it is.

## Evidence before `done`, and the optional per-task review

Two halves of change 035, priced differently on purpose.

**The verification footer ships on, and is not configurable.** Every coding-agent prompt ends with a
required block — `Command:`, `Exit:`, `Output (tail):` — and
`specclaw-build check-report <report>` gates the move to `complete` on it: the footer must exist,
`Command:` must be non-empty, and `Exit:` must be `0`. Anything else marks the task `failed` with
`no-verification-evidence` and re-dispatches it through the normal retry path.

This is not a feature with a trade-off. A task that cannot show what it ran, and that the run exited
0, should not be `done`; agents routinely report *"implemented and tested"* having run nothing, and
this is the only place a **script** can catch it. There is no docs-only exemption —
`Command: ls docs/thing.md` · `Exit: 0` is a legitimate footer and costs nothing, and an exemption
would be a hole shaped exactly like the failure.

**`check-report` is fence-aware, and reads the LAST footer.** A report routinely quotes the footer
template it was handed, or pastes an earlier attempt, putting a literal `## Verification` / `Exit: 0`
inside a code block — which a fence-blind check reads as evidence that something ran. Same rule, and
the same reason, as `specclaw-parse-tasks`. Taking the *last* footer means a retry is judged on the
retry.

**The per-task review gate ships off** (`build.task_review: off | spec | full`). After a task's
commit, `specclaw-build review-package` writes `changes/<change>/reviews/<task>.diff` — base and head
SHAs, the task brief from `tasks.md`, the stat and the diff, capped at 4000 lines **with a visible
truncation marker**, because a reviewer handed a silently-shortened diff approves the half it was
shown. It is read-only with respect to git: no checkout, no stash, no add, so it cannot disturb an
in-flight task in a parallel wave.

The reviewer is the **existing** `code-reviewer` seat with a task-scoped prompt — read the diff file
once, **do not crawl the repo**, spec compliance first and quality second. Without the read-once rule
a per-task reviewer re-reads the codebase once per task, and an unaffordable gate is a gate that gets
switched off. It always runs on `models.review`, never the `dynamic_agents` ladder: the ladder sizes
implementation difficulty, and reading one task's diff is not that work.

Bash owns the verdict's consequence, as always: `BLOCK` marks the task failed and re-dispatches it,
`WARN`/`NOTE` are recorded and the task proceeds. **A `BLOCK` shares the task's normal retry budget**
— two counters would let a task alternate between failing tests and failing review and exhaust
neither.

It ships `off` because `full` doubles agent spawns per task and the gate's value has not been
measured; the same one-release rollout `workflow.code_review_block` and `party.default` took. The
whole-change reviewer at verify is told the per-task findings exist and must not repeat them.

## Skill descriptions: the lint, and the rule for editing one

A skill's `description:` is its **only** routing surface, and it is the one part of specclaw that
nothing else measures. superpowers measured what a long one costs: an agent given a description that
summarised the workflow *followed the description and skipped the skill body* — one review instead of
the two the flowchart required. Every extra sentence is a chance for the model to stop reading there.

`tests/run-description-lint-tests.sh` runs on every push and checks three rules:

| Rule | Check |
|---|---|
| `LEN` | ≤ 300 characters |
| `TRIGGER` | contains a clause from the **closed** set: `Use when` · `Use after` · `Use before` · `Run after` · `Run before` · `Invoke when` · `Invoke immediately when` · `Trigger when` · `Called when` · a `when …` condition |
| `NARRATION` | no `→`, no ` then `, no `Step N`, no `first … then` |

`disable-model-invocation: true` skills are exempt from `TRIGGER` — nothing routes to them by
description — and still owe `LEN` and `NARRATION`.

**The trigger set is closed on purpose.** Any list broad enough to admit *"Show the project's
dashboard"* also admits *"Manage …"*, *"Create …"*, *"Produce …"*, *"Synthesize …"* — which is every
description in this repo, at which point the rule checks nothing. The cost of that decision is a
large day-one offender list in `tests/description-lint-baseline.txt`; the benefit is that the rule
means something.

**The baseline is a debt register, not a licence.** Same format and same discipline as
`shellcheck-baseline.txt`: `<path> <RULE>` pairs, no line numbers, and a fixed offence is reported as
prunable rather than silently accepted, so the list can only shrink. **A new skill gets no entries**
and must pass outright from its first commit — `skills/debug` and `skills/using-specclaw` landed
alongside the lint and are not in it. Never add an entry to silence a description you just wrote.

**Any PR that edits a `SKILL.md` description, or the router in `skills/using-specclaw/`, carries the
trigger matrix in its body.** Routing is stochastic and invisible; a rewrite that reads better and
routes worse is indistinguishable from one that helped, unless it was measured.

```
SPECCLAW_TRIGGER_EVALS=1 bash plugins/specclaw/tests/run-trigger-tests.sh   # before
# …edit the description…
SPECCLAW_TRIGGER_EVALS=1 bash plugins/specclaw/tests/run-trigger-tests.sh   # after
```

`specclaw-pr` attaches the newest `tests/results/triggers-*.md` automatically. The suite costs API
calls, so it is opt-in behind `SPECCLAW_TRIGGER_EVALS=1` and runs in CI nightly and on PRs touching
`skills/**/SKILL.md` or `hooks/**` — never on every push. It asserts on the **`Skill` tool
invocation** in `claude -p --output-format json`, never on prose: a model that says *"I'll use the
propose skill"* and invokes nothing is the exact failure being measured. And it **fails loudly** when
no row produces a recognisable tool-use block, because `claude -p` output-format churn would
otherwise read as a total routing collapse.

`tests/fixtures/triggers.tsv` holds the utterances. **Negative rows (`expect = none`) are not
optional** — over-triggering is the failure mode a MUST gate produces, and a positive-only suite
scores 100% on a router that fires for every sentence. Two rows share the utterance *"the tests are
failing"* and differ only in seeded state; they are the sharpest test of the claim that 033's state
snapshot makes routing controlled rather than persuasive.

## Templates

Templates live in `templates/`. `context.md` is the seed for new projects — copy it to `.specclaw/context.md` or let `/specclaw:context add` create it automatically.
