# Spec: Core — context gate with hand-off, task sizing by context, model by agent type

**Change:** 065-core-context-gate-task-sizing
**Created:** 2026-11-14
**Status:** 🟡 Draft

## Overview

A subagent cannot see its own token count, and quality falls long before the window is full
(ION-TBML-SUITE ADR-0017, decisions 33, 35, 43, 55, 56). This change ports TBML's context gate
(`.claude/hooks/dl-gate.py` and `scripts/dev_loop/dashboard/gate.py`, at 1bdac92b9) and the task
sizing of `dev-loop-task-sizing` into core, in Python 3 stdlib, without TBML's dashboard, control
file, or law. Open questions settled by the operator: the gate ships `warn`; Python; Claude Code
only; `specclaw-budget` is a fixed contract for change 063.

## Requirements

### Functional Requirements

- **FR-1 Config.** `budget:` in `config.yaml` holds `gate: off|warn|block` (default `warn`),
  `roles.<role>.context` (per-role override) and `routing.<kind>: <agent type>` (plus
  `routing.default`). Shipped role defaults: `builder-backend` 200000, `builder-frontend` 200000,
  `code-reviewer` 150000, `general` 200000. A role's range is `default/2 .. default*2`. The block
  is read block-scoped (the `party_val` rule), never with a whole-file grep.
- **FR-2 Bad config.** An unknown `gate` value, a non-integer or out-of-range `context`, or an
  unknown role name is ignored with a warning; the default stands. The config never stops the gate
  from running.
- **FR-3 `specclaw-budget roles --json [<specclaw_dir>]`** prints one JSON object
  `{"<role>": {"context", "default", "min", "max", "source": "default"|"config"}}` for every role.
- **FR-4 `specclaw-budget set <specclaw_dir> <role> <n>`** writes `budget.roles.<role>.context: <n>`
  inside the `budget:` block (creating the block, the `roles:` map or the role as needed) and
  changes no other line. Unknown role or `n` outside `min..max`: exit 1, nothing written. Wrong
  arguments: exit 2.
- **FR-5 Gate hook.** `hooks/context-gate`, a `PreToolUse` command hook registered in
  `hooks/mod.json` (Claude Code only). It reads the event on stdin:
  - no `agent_id` (the main session), `budget.gate: off`, or no `.specclaw/config.yaml` in the
    event cwd or its git toplevel: exit 0, no output;
  - otherwise it reads the subagent's own transcript
    (`<transcript_path minus .jsonl>/subagents/agent-<agent_id>.jsonl`), takes the last assistant
    record's context (`input + cache_creation + cache_read`), and the role: the prompt's first-line
    `specclaw budget: role=<role> context=<n>` role when known, else the `agent_type` after its last
    `:` when it names a role, else `general`. The cap is the role's context, or the stated `n`
    clamped to the role's range.
  - below 90% of the cap: exit 0, no output.
  - at or over 90%, `warn`: exit 0 with one `systemMessage` line and an `additionalContext` naming
    the hand-off steps; never denies. A line is logged.
  - at or over 90%, `block`: a Bash call whose every command is `git add`, `git commit`,
    `git status`, `git diff`, `git log`, `cd` or `specclaw-budget handover` passes with the same
    note; any other call is denied (exit 2, reason on stderr naming the hand-off steps). Logged.
- **FR-6 Fail open, loud** (decision 49). Any exception: exit 0, one `systemMessage` line saying
  the call went through, and a line in the log. The log is
  `${SPECCLAW_GATE_LOG_DIR:-~/.claude/specclaw}/gate.jsonl`, moved to `gate.1.jsonl` past 1 MiB.
- **FR-7 Hand-off record.** `specclaw-budget handover <specclaw_dir> <change> <task> <next...>`
  appends `{"kind":"handover","at","task","next"}` to `changes/<change>/timeline.jsonl`.
- **FR-8 Task sizing.** Tasks may carry `- Context: <n>`. `specclaw-budget estimate <specclaw_dir>
  <change>` prints, per task with `Files:`, `<id> read=<tokens> context=<n>` where read is
  `26000 + chars(existing Files)/2.2` and context is the task's `Context:` or else read; it exits 1
  naming every task over 60000 (`split it`). The full plan reference tells the planner to run it,
  add the expected diff (about 60 tokens a typed line), write `Context:`, and split any task over
  60k before build.
- **FR-9 Brief.** `specclaw-budget brief <specclaw_dir> <change> <task>` prints
  `subagent_type: <agent>` (from `routing.<Kind>`, else `routing.default`) and the budget line
  `specclaw budget: role=<role> context=<n>` (no `context=` without a `Context:`). The full build
  reference dispatches each task on that agent type with the budget line opening its prompt.
- **FR-10 Record.** `specclaw-budget record <specclaw_dir> <change> <task> <agent_id>` appends
  `{"kind":"task_context","at","task","agent","estimate","peak"}` to `timeline.jsonl`, the peak
  read from that agent's transcript (null when not found). Build runs it after each task agent.
- **FR-11 Model by agent type.** `agents/builder-backend.md` (`model: opus`) and
  `agents/builder-frontend.md` (`model: sonnet`). Default routing: `frontend` and `docs` →
  `specclaw:builder-frontend`; `default` → `specclaw:builder-backend`.
- **FR-12 Ledger readers.** `specclaw-timer` skips `handover` and `task_context` lines as it skips
  `lesson` lines.

### Non-Functional Requirements

- **NFR-1** Python 3 stdlib only. A main-session call exits before `json` loads.
- **NFR-2** `hooks/hooks.json` (read by Codex) does not gain the hook.
- **NFR-3** New suite `tests/run-context-gate-tests.sh` (bash + coreutils + python3), registered in
  `ci.yml`. No shellcheck baseline entries. No new SKILL.md.

## Acceptance Criteria

- [ ] **AC-1:** `roles --json` prints all four roles with `context/default/min/max/source`; a config
      override shows `source: config`; a decoy `context:` key in another block is not read.
- [ ] **AC-2:** `set` writes inside the `budget:` block only (other bytes unchanged), creates a missing
      block, refuses an unknown role and an out-of-range value with exit 1 and no write, and a bad
      argument list with exit 2.
- [ ] **AC-3:** The hook is silent with exit 0 for a main-session event, `gate: off`, no config, and a
      subagent under 90% of its cap.
- [ ] **AC-4:** `warn` at 90%: exit 0, valid JSON with a `systemMessage`, never a deny, one log line.
- [ ] **AC-5:** `block` at 90%: `git commit` and `specclaw-budget handover` pass; `Edit` and
      `rm -rf x` and `git add . && rm x` are denied with exit 2.
- [ ] **AC-6:** Role and cap: an unknown `agent_type` is `general`; `specclaw:builder-frontend` is
      `builder-frontend`; a stated `context=` is clamped to `default/2..default*2`.
- [ ] **AC-7:** Fail open: a torn event or an unreadable transcript exits 0 with a `systemMessage`
      and a log line; a bad `gate:` value runs on `warn` and says so.
- [ ] **AC-8:** `estimate` computes `read` from file sizes, prefers `Context:`, and exits 1 naming a
      task over 60000; `brief` routes by Kind; `record` appends a `task_context` line with the
      transcript peak; `handover` appends a `handover` line; `specclaw-timer report` stays silent
      about them.
- [ ] **AC-9:** `mod.json` registers `context-gate` under `PreToolUse`; `hooks.json` does not; the two
      builder agents exist with `opus` and `sonnet`; the new suite is in `ci.yml`.

## Edge Cases

- A transcript with no assistant record yet: no context, no gate.
- A half-written last transcript line: skipped.
- A transcript over 64 MiB: only the last 64 MiB is read.
- `agent_id` that is not a plain id: fail open (it would build a path).

## Dependencies

- 059 (merged): `timeline.jsonl` and its `kind` lines.
- 063 (parallel): calls `specclaw-budget roles --json` and `set`.

## Notes

- The "dispatch on Opus when the budget allows" text the proposal names to remove does not exist in
  this repo (`git grep -i 'budget allows'` is empty at 5199148); there is nothing to remove.
- TBML's ten-call wrap-up window, pauses and `control.json` are dashboard features and are not
  ported; `block` denies all but committing until the agent stops.
