# Design: Core — context gate with hand-off, task sizing by context, model by agent type

**Change:** 065-core-context-gate-task-sizing
**Created:** 2026-11-14

## Technical Approach

One stdlib Python module, `lib/budget.py`, holds every rule: the block-scoped `budget:` reader and
writer, the role table and clamp, the transcript tail reader, the gate decision, the task-block
reader. Two thin entry points import it: `hooks/context-gate` (the PreToolUse hook) and
`bin/specclaw-budget` (the CLI 063 and the skills call). One implementation, as TBML moved
`caps_of` into `gate.py` so the hook and the dashboard could not disagree.

## Architecture

```
PreToolUse event ──> hooks/context-gate ──> lib/budget.py ──> allow | note | deny
                       (main session: exit before json)      log: ~/.claude/specclaw/gate.jsonl
specclaw-budget roles|set|estimate|brief|record|handover ──> lib/budget.py
plan (full ref) ── estimate ──> Context: lines      build (full ref) ── brief ──> Agent(subagent_type, budget line)
                                                                     └─ record ──> timeline.jsonl
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/lib/budget.py` | create | config read/write, roles, gate decision, transcript, tasks |
| `plugins/specclaw/hooks/context-gate` | create | PreToolUse hook, fail open |
| `plugins/specclaw/bin/specclaw-budget` | create | CLI: roles, set, estimate, brief, record, handover |
| `plugins/specclaw/hooks/mod.json` | modify | register `PreToolUse` → context-gate |
| `plugins/specclaw/agents/builder-backend.md` | create | opus builder |
| `plugins/specclaw/agents/builder-frontend.md` | create | sonnet builder |
| `plugins/specclaw/bin/specclaw-timer` | modify | skip `handover` / `task_context` lines |
| `plugins/specclaw/templates/config.yaml` | modify | `budget:` block |
| `plugins/specclaw/templates/tasks.md` | modify | `Context:` field, `frontend`/`backend` kinds |
| `plugins/specclaw/references/full/plan.md` | modify | task sizing step |
| `plugins/specclaw/references/full/build.md` | modify | brief, budget line, record |
| `plugins/specclaw/CLAUDE.md`, `MOD.md` | modify | the gate section, tests row |
| `plugins/specclaw/tests/run-context-gate-tests.sh` | create | suite |
| `.github/workflows/ci.yml` | modify | register suite |

## Data Model Changes

`config.yaml`:

```yaml
budget:
  gate: warn            # off | warn | block
  routing:              # task Kind -> agent type; default for any other Kind
    frontend: specclaw:builder-frontend
    docs: specclaw:builder-frontend
    default: specclaw:builder-backend
  roles:
    builder-backend:
      context: 200000
```

`timeline.jsonl` gains `{"kind":"handover",...}` and `{"kind":"task_context",...}` lines (no `ev`,
no `ts`, like 059's `lesson`).

## API Changes

`specclaw-budget` — `roles --json [dir]`, `set dir role n` (fixed for 063), `estimate dir change`,
`brief dir change task`, `record dir change task agent_id`, `handover dir change task next...`.

## Key Decisions

- **D1 Ships `warn`.** The gate is unproven outside TBML; a wrong `block` stops every subagent.
  `warn` puts the hand-off text in front of the agent and the user without denying anything.
  This repo's own config stays on the default.
- **D2 No wrap-up window.** TBML granted ten Bash calls after the crossing and counted them in a
  per-agent file. Here `block` allows only committing commands, for as long as the agent runs, so
  there is no state file. The agent commits, writes the hand-off, and stops.
- **D3 Allow-list by command prefix.** Quoted strings are blanked first (a commit message holds any
  text), then the command is split on `&&`, `||`, `;`, `|` and newlines; every part must start with
  an allowed prefix. Shortcut: an unquoted `$(...)` inside an allowed command is not inspected —
  the gate is a quality cap on a cooperative agent, not a sandbox.
- **D4 Role from the type, the prompt may name it.** The type after its last `:` is the role when
  the table has it (so `specclaw:builder-backend` and a project's own `builder-backend` agree), a
  known `role=` in the budget line wins (a `general-purpose` agent dispatched for a builder task),
  and anything else is `general` (decision 42).
- **D5 The clamp range is fixed to the shipped default** (`default/2..default*2`), not the
  configured context, so 063 shows a stable range. A sized task under 100k is clamped up to the
  builder minimum; the estimate still matters for splitting at plan time and for the record.
- **D6 Log outside the repo.** `~/.claude/specclaw/gate.jsonl`, rotated past 1 MiB, holds ids,
  numbers and error types only — never prompt or tool text.
- **D7 Hook stays out of `hooks/hooks.json`.** Codex reads that file; nothing shows Codex accepts a
  PreToolUse command hook with this event shape (same reasoning as 060's done-guard).

## Risks & Mitigations

- A gate bug stops all subagents → ships `warn`; every exception fails open; `gate: off` exits
  before reading anything.
- Hook latency on every tool call → main-session calls exit after a byte search, before `json`.
- Claude Code changes the transcript layout → no transcript, no context, no gate (allow).

## Grounding sources

- TBML `.claude/hooks/dl-gate.py` @1bdac92b9: transcript path from `agent_id`, 1 MiB backward tail
  read bounded at 64 MiB, half-written last line skipped, fail open with one line and a rotated log.
- TBML `scripts/dev_loop/dashboard/gate.py`: `spent()` trips at `context >= cap * 0.9`; hand-off
  text "commit, then ... handover ... then stop".
- TBML `scripts/dev_loop/defaults.yaml`: role caps, `general` with `agent_types: ["*"]`,
  `routing.kinds: {backend: builder-backend, frontend: builder-frontend}`.
- TBML `dev-loop-task-sizing/spec.md`: estimate `start + chars/chars_per_token + lines × 60`,
  `start 26000`, `chars_per_token 2.2`, limit 60000.
- `plugins/specclaw/CLAUDE.md` "Party config reads": "No party config value may be read any other
  way" — the same block-scoped rule applies to `budget:`.
