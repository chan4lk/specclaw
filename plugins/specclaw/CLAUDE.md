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
| `specclaw-party` | Adversarial proposal panel: `panel` (resolve the roster) / `tally` (compute the verdict) / `report` (assemble `party-report.md`) / `get` (**the only reader of the `party:` block**) — see below |

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
| `run-status-row-tests.sh` | `status-row` upserts, and the two sed defects it replaced |
| `run-phase-state-tests.sh` | `set-phase` transitions and `reconcile` drift detection |
| `run-loop-gate-tests.sh` | `loop gates` report readers — BLOCK counting and verdict extraction |
| `run-change-numbering-tests.sh` | `next-change-number` derivation, `renumber-changes` plan/refusals/backfill |
| `run-party-tests.sh` | party seat resolution and clamping, the fail-loud fallback, the panel cache, the verdict tally, the report grammar, and the `party_val` config-collision regression |

`shellcheck-gate.sh` fails CI on any shellcheck finding absent from `shellcheck-baseline.txt` (pairs of `<path> <SCxxxx>`, no line numbers, so unrelated edits do not churn it). Fix a new finding or add a targeted `# shellcheck disable=SCxxxx` with a rationale — never silence one by appending to the baseline. It skips with exit 0 when shellcheck is not installed, so the suite still runs locally.

## Templates

Templates live in `templates/`. `context.md` is the seed for new projects — copy it to `.specclaw/context.md` or let `/specclaw:context add` create it automatically.
