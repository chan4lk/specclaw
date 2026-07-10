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

## Scripts

All executable scripts live in `bin/`. Key ones:

| Script | Purpose |
|--------|---------|
| `specclaw-ensure-init` | Idempotently init `.specclaw/` |
| `specclaw-build-context` | Build coding agent payload (includes context.md; `--failure-record`/`--reflection` for loop remediation) |
| `specclaw-loop` | Autonomous loop controller: `init` / `gates` / `decide` / `guard-tests` / `log-turn` / `escalate` / `ci-poll` / `done` |
| `specclaw-update-context` | Output LLM prompt to rewrite context.md post-merge |
| `specclaw-update-status` | Regenerate `.specclaw/STATUS.md` dashboard |
| `specclaw-gh-sync` | GitHub Issues sync |
| `specclaw-pr` | Create GitHub PR (enforces test policy, triggers context update) |
| `specclaw-validate-change` | Check phase prerequisites |

## Templates

Templates live in `templates/`. `context.md` is the seed for new projects — copy it to `.specclaw/context.md` or let `/specclaw:context add` create it automatically.
