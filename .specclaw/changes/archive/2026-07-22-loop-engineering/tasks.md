# Tasks: Loop Engineering — Autonomous Build→Verify→Review Loop

**Change:** loop-engineering
**Created:** 2026-07-10
**Total Tasks:** 10

## Summary

Build the `specclaw-loop` controller (gates, guardrails, state/log, CI poll), a `/specclaw:loop` orchestrator skill, wire the failure-record feedback into `specclaw-build-context`, add the `loop:` config block (default-on), update the affected skills + docs, and bump the version. Wave 1 lays the config + controller skeleton; wave 2 adds the guardrails, reward-hack guard, and CI tier; wave 3 wires the skill and existing lifecycle skills; wave 4 documents and bumps.

## Tasks

### Wave 1 — Foundation: config schema + controller core

- [x] `T1` — Add `loop:` config block (default-on) to init + template
  - Files: `plugins/specclaw/bin/specclaw-init`, `plugins/specclaw/templates/config.yaml`
  - Estimate: small
  - Notes: Emit `loop:` block with defaults from design (`enabled: true`, `max_iterations: 5`, `no_progress_limit: 2`, `guard_action: revert-tests`, `test_paths: []`, `ci_gate: false`, `ci_max_iterations: 3`, `ci_timeout_seconds: 1200`). Reuse existing `yaml_val` reading convention.

- [x] `T2` — `specclaw-loop` skeleton: `init`, `gates`, `done`, `--help`
  - Files: `plugins/specclaw/bin/specclaw-loop`
  - Estimate: large
  - Notes: Bash + git + coreutils, `set -euo pipefail`, copy `yaml_val`/`die`/`warn`/`json_escape` helpers from `specclaw-verify`. `init` seeds `loop-state.json` + `loop-log.md`. `gates` runs the four local gates (tasks-complete via `specclaw-parse-tasks`, test/lint/build commands, verify verdict from `verify-report.md`, review BLOCK count from `review-report.md`) and emits JSON `{all_green, passing_count, gates:[{name,green,errors,files}]}`. `done` emits final PASS summary. Executable bit set.

### Wave 2 — Guardrails, reward-hack guard, CI tier

- [x] `T3` — Signature + `decide` (cap / no-progress / regression / oscillation)
  - Files: `plugins/specclaw/bin/specclaw-loop`
  - Estimate: large
  - Depends: T2
  - Notes: `failure_sig = sha1(sorted red gates + normalized error fingerprint)` (strip line numbers/timestamps). `decide` reads `loop-state.json` + args (`passing_count`, `failure_sig`), applies FR4–FR7, emits `{action, reason}`. `log-turn` appends to `loop-log.md` and updates `loop-state.json` (turn, passing_count, sig_history, ci_turn).

- [x] `T4` — Reward-hack guard: `guard-tests`
  - Files: `plugins/specclaw/bin/specclaw-loop`
  - Estimate: medium
  - Depends: T2
  - Notes: After fix turn, intersect `git diff --name-only` with `loop.test_paths` globs. On hit: per `guard_action`, revert test files (`revert-tests`) or the whole turn (`revert-turn`); log `reward_hack_guard` trip; mark turn as non-progress failure. Tests execute from committed HEAD, never agent-staged same-turn changes.

- [x] `T5` — `escalate` + state preservation
  - Files: `plugins/specclaw/bin/specclaw-loop`
  - Estimate: medium
  - Depends: T3
  - Notes: Commit partial work (specclaw prefix), keep worktree intact (warn if `git.strategy: direct`), finalize `loop-log.md`, emit operator notification text stating halt reason + current gate status.

- [x] `T6` — CI outer loop: `ci-poll`
  - Files: `plugins/specclaw/bin/specclaw-loop`
  - Estimate: large
  - Depends: T3
  - Notes: When `loop.ci_gate: true`. GitHub: `gh pr checks` / `gh run view --log-failed`. Azure: `az pipelines runs`. Emit `{status: green|red|timeout|no-checks, failed_log}`. Honor `ci_max_iterations` + `ci_timeout_seconds`; "no checks after grace" → green + warn. In-session polling only (no MCD).

### Wave 3 — Feedback wiring + orchestrator skill + lifecycle integration

- [x] `T7` — `specclaw-build-context`: `--failure-record` / `--reflection`
  - Files: `plugins/specclaw/bin/specclaw-build-context`
  - Estimate: medium
  - Depends: T2
  - Notes: Optional flags inject failure record + reflection + "smallest diff to turn the failing gate green" instruction into the remediation payload. Backward compatible: omitted = current behavior.

- [x] `T8` — `/specclaw:loop` orchestrator skill
  - Files: `plugins/specclaw/skills/loop/SKILL.md`
  - Estimate: large
  - Depends: T3, T4, T5, T6, T7
  - Notes: Orchestrate per design: init → turn loop (gates → done? / decide → halt? / build reflection+record → build-context --failure-record → spawn fix agent (models.coding) → guard-tests → commit → log-turn) → optional CI tier after PR push. `ensure_init` first. Notifications on done/halt.

- [x] `T9` — Wire loop into build/verify/pr skills
  - Files: `plugins/specclaw/skills/build/SKILL.md`, `plugins/specclaw/skills/verify/SKILL.md`, `plugins/specclaw/skills/pr/SKILL.md`, `plugins/specclaw/skills/pr-azdo/SKILL.md`
  - Estimate: medium
  - Depends: T8
  - Notes: build/verify note loop behavior when `loop.enabled`; verify replaces manual-only remediation with loop remediation reference; pr/pr-azdo trigger CI outer loop when `loop.ci_gate: true` after push. Preserve single-pass path when `loop.enabled: false` (AC9).

### Wave 4 — Docs + version bump

- [x] `T10` — Document loop + bump version
  - Files: `plugins/specclaw/CLAUDE.md`, `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Depends: T8, T9
  - Notes: Document loop tier, `/specclaw:loop`, `loop:` config block, reward-hack guard, CI tier + MCD boundary. Patch-bump version in both files (keep in sync).

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
