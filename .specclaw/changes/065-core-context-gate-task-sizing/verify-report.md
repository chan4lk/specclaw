# Verify report: 065-core-context-gate-task-sizing

**Verdict:** PASS WITH FOLLOW-UPS

## Acceptance criteria

| AC | Result | Evidence |
|----|--------|----------|
| AC-1 roles --json | met | run-context-gate-tests.sh: four roles, config source, decoy `context:` in `models:` not read |
| AC-2 set | met | writes in block only, keeps comment and indentation, creates block, refuses unknown/out-of-range (1) and usage (2), refuses inline maps |
| AC-3 silent paths | met | main session, `gate: off`, no config, under 90% |
| AC-4 warn | met | exit 0, systemMessage, additionalContext with hand-off, one log line |
| AC-5 block | met | commits, handover (also via quoted plugin path), fd/`/dev/null` redirects pass; Edit, `rm`, chained commands, file redirects, `--output`, other filters denied |
| AC-6 role and cap | met | `specclaw:` prefix, `general` fallback, clamp both ways, malformed stated role/context loud |
| AC-7 fail open | met | torn event, bad transcript, bad agent id, missing transcript, 64 MiB and 1 MiB limits, unwritable log after a deny, bad gate value |
| AC-8 estimate/brief/record/handover/timer | met | formula, Context wins, unsized and malformed refused, routing, ledger lines, timer silent |
| AC-9 wiring | met | PreToolUse in mod.json only, builder agents opus/sonnet, suite in ci.yml |

## Checks

- `run-context-gate-tests.sh`: all PASS (90+ rows).
- All 66 suites in ci.yml: the same 14 fail as on main (change-numbering, long-orchestration, phase-state,
  synth-agent, 9 specclaw-bf, party). No new failures. Re-ran the touched suites after the last fix: context-gate,
  timing, plugin-split, codex-plugin, lean-flow, description-lint, suggest, done-guard all green; run-mod-tests green.
- Shellcheck gate: no new findings.
- Size cap: 678 production lines over the 400 cap, with the waiver in proposal.md.

## Review

Review: ESCALATE after 10 rounds (sonnet rounds, opus final). Rounds 1-9 findings were fixed. The last final
pass reported 0 blockers, 4 majors, 1 minor, all recorded in follow-ups.md. `specclaw-review verdict` exits 1;
the PR is raised with those follow-ups named, per the builder's round cap.
