# Design: Loop Engineering — Autonomous Build→Verify→Review Loop

**Change:** loop-engineering
**Created:** 2026-07-10

## Technical Approach

A new bash controller `specclaw-loop` owns all mechanical loop logic (gate evaluation, signature computation, progress/regression/oscillation detection, halt decisions, state/log persistence). A new `/specclaw:loop` skill is the orchestrator: it calls the controller for decisions and spawns the fix / verify / review agents. This mirrors the existing split — scripts do deterministic work, skills drive the LLM steps.

The loop **reuses** existing engines: `specclaw-parse-tasks` (task-completion gate), `specclaw-verify` (verify gate), the `code-reviewer` agent (review gate), and `build.{test,lint,build}_command` (test gates). It does not reimplement any of them.

State lives in two files per change:
- `loop-state.json` — machine state: turn number, per-turn passing-gate count, last failure signature, signature history (for oscillation), CI turn count.
- `loop-log.md` — human/audit trail: one entry per iteration.

## Architecture

```
/specclaw:loop <change>
  │
  ├─ specclaw-loop init      → seed loop-state.json + loop-log.md
  │
  └─ repeat (turn = 1..max_iterations):
       ├─ specclaw-loop gates .specclaw <change>
       │     → runs: tasks-complete? tests? verify PASS? review 0 BLOCK?
       │     → emits JSON: {all_green, gates:[{name,green,errors,files}], passing_count}
       │
       ├─ if all_green → specclaw-loop done → exit PASS
       │
       ├─ specclaw-loop decide .specclaw <change> <passing_count> <failure_sig>
       │     → checks: cap? no-progress? regression? oscillation?
       │     → emits: {action: "continue"|"halt", reason}
       │
       ├─ if halt → specclaw-loop escalate (commit partial, keep worktree, notify) → exit
       │
       └─ else:
            ├─ build reflection + failure record (from gates JSON)
            ├─ specclaw-build-context ... --failure-record <file>   (remediation payload)
            ├─ spawn fix agent (models.coding)
            ├─ specclaw-loop guard-tests .specclaw <change>   → reject turn if test files touched
            ├─ commit fix
            └─ specclaw-loop log-turn ...   (append to loop-log.md, update loop-state.json)

  (opt-in, after PR push, loop.ci_gate: true)
  └─ repeat (ci_turn = 1..ci_max_iterations):
       ├─ specclaw-loop ci-poll .specclaw <change>   → gh pr checks / az pipelines
       ├─ if green → done
       ├─ if timeout/cap → escalate
       └─ else pull failed logs (gh run view --log-failed) → fix cycle → push → re-poll
```

### Failure signature

`failure_sig = sha1( sorted(red_gate_names) + normalized_error_fingerprint )`. Normalization strips line-number noise and timestamps so "same error, different run" collapses to one signature. Stored in `loop-state.json` history; drives no-progress (identical consecutive), oscillation (Nth identical / A→B→A), and new-vs-repeat flag in the failure record.

### Reward-hacking guard (`guard-tests`)

After the fix agent runs, `git diff --name-only` is intersected with the test-file globs (derived from `build.test_command` conventions + a configurable `loop.test_paths` glob list). Any intersection → turn rejected, logged as `reward_hack_guard` trip, diff of the test files reverted (or the whole fix turn reverted per `loop.guard_action`), and the turn counts as a failure (does not advance progress). Tests are executed from the committed HEAD reference, never from agent-staged changes within the same turn.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/bin/specclaw-loop` | Create | Controller: `init`, `gates`, `decide`, `guard-tests`, `log-turn`, `escalate`, `done`, `ci-poll`, `--help`. Bash + git + coreutils; `gh`/`az` for ci-poll. |
| `plugins/specclaw/skills/loop/SKILL.md` | Create | `/specclaw:loop` orchestrator skill. |
| `plugins/specclaw/bin/specclaw-build-context` | Modify | Accept optional `--failure-record <file>` + `--reflection <file>` and inject into the remediation payload. |
| `plugins/specclaw/templates/config.yaml` (or init default) | Modify | Add `loop:` block with defaults (`enabled: true`, caps, `no_progress_limit`, `ci_gate`, `test_paths`, `guard_action`, `ci_timeout_seconds`). |
| `plugins/specclaw/bin/specclaw-init` | Modify | Emit the new `loop:` block in generated `config.yaml`. |
| `plugins/specclaw/skills/build/SKILL.md` | Modify | Note: when `loop.enabled`, build is a loop turn; single-pass otherwise. |
| `plugins/specclaw/skills/verify/SKILL.md` | Modify | Reference loop remediation instead of manual-only remediation. |
| `plugins/specclaw/skills/pr/SKILL.md` + `pr-azdo/SKILL.md` | Modify | Trigger CI outer loop when `loop.ci_gate: true` after push. |
| `plugins/specclaw/CLAUDE.md` | Modify | Document loop tier, `/specclaw:loop`, `loop:` config, reward-hack guard. |
| `plugins/specclaw/.claude-plugin/plugin.json` | Modify | Version bump. |
| `.claude-plugin/marketplace.json` | Modify | Version bump (in sync). |

## Data Model Changes

**`config.yaml` — new `loop:` block:**
```yaml
loop:
  enabled: true            # default-on
  max_iterations: 5        # local inner loop cap
  no_progress_limit: 2     # consecutive identical/empty turns → halt
  guard_action: "revert-tests"   # revert-tests | revert-turn
  test_paths: []           # globs identifying test files (reward-hack guard)
  ci_gate: false           # opt-in outer CI loop
  ci_max_iterations: 3
  ci_timeout_seconds: 1200 # per-cycle CI wall-clock before halt
```

**`loop-state.json` (per change):**
```json
{ "turn": 0, "passing_count": 0, "sig_history": [], "ci_turn": 0 }
```

**`loop-log.md` (per change):** markdown, one `## Turn N` section per iteration with gate table, signature, reflection, action, decision.

## API Changes

- `specclaw-loop <subcommand>` — new CLI (see file map).
- `specclaw-build-context` gains optional `--failure-record` / `--reflection` flags (backward compatible — omitted = current behavior).

## Key Decisions

1. **Controller owns guardrails, skill owns LLM steps** — matches existing script/skill split; guardrails are code (a law), not prompt text (a suggestion).
2. **Whole-change re-verify each turn** (per operator decision) — simpler, catches cross-gate regressions; accept the extra cost.
3. **Default-on** (per operator decision) — ships enabled; correctness of guardrails is therefore gating.
4. **CI tier reuses `gh`/`az`, lives in specclaw** — MCD only for detached runs (out of scope).
5. **Signature-based detection** rather than semantic diffing — cheap, deterministic, no extra LLM calls for control flow.
6. **Reward-hack guard defaults to `revert-tests`** — least destructive; agent keeps source progress, loses only illegal test edits.

## Risks & Mitigations

- **R1 — Runaway spend (default-on).** Mitigated by iteration cap + no-progress + regression tripwire, all checked before the next spawn. → Verified by AC2/AC3/AC4.
- **R2 — Reward hacking slips through.** Highest-risk. Mitigated by test-file diff rejection + pinned test execution. → Verified by AC5; verify phase must exercise it adversarially.
- **R3 — Signature normalization too aggressive/loose.** Too loose → misses no-progress; too tight → false oscillation halts. → Start conservative (strip only line numbers/timestamps), tune via loop-log evidence.
- **R4 — CI polling hangs.** Mitigated by `ci_timeout_seconds` + "no checks = green after grace" rule. → Verified by AC8 + edge cases.
- **R5 — Backward-compat break.** Mitigated by `loop.enabled: false` restoring single-pass exactly. → Verified by AC9.
