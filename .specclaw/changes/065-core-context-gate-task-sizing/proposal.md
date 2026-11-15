# Proposal: Core — context gate with hand-off, task sizing by context, model by agent type

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** 059-core-records-suggest

## Problem

In ION-TBML-SUITE, agents that bundled several jobs into one launch peaked at 160k–269k context, and quality
fell long before the window was full. Single-job agents peaked at 34k–60k (ADR-0017 decisions 35, 43, 55, 56).
A subagent cannot see its own token count, so only a hook can stop it at a cap (decision 33). The model also
has to come from structure, not from the dispatcher's memory (decision 46): on one day all eight builders ran
on the wrong model.

**Timing:** TBML's impact verdict is due 2026-11-19, and its gate code lives only on an unmerged preview branch.
Plan this change after that verdict and port from the code that lands on TBML `develop`.

## Proposed Solution

1. **Context gate:** a `PreToolUse` command hook in core. It reads the calling subagent's transcript usage and
   the role's cap, `budget.roles.<role>.context` (defaults shipped; the project overrides). At 90% of the cap
   it denies further work except committing, and tells the agent to write a `handover` line to
   `timeline.jsonl` and stop. The dispatcher then starts a fresh agent from that hand-over. It fails open and
   loud: a crash lets the call through, logs, and prints one line (decision 49). An untyped subagent gets the
   `general` role (decision 42). The main session is uncapped.
2. **Per-launch budget:** an agent's prompt may open with `specclaw budget: role=<role> context=<n>`. The gate
   clamps it to the role's range (half to double the default).
3. **Task sizing:** `/specclaw:plan` estimates each task's context (files read plus the expected diff) and splits
   any task over about 60k before build. The estimate becomes that task's launch budget. Build records the
   estimate against the actual peak in `timeline.jsonl`.
4. **Model by agent type:** `builder-backend` (Opus) and `builder-frontend` (Sonnet) agents, chosen by a
   task-kind routing in config. The "dispatch on Opus when the budget allows" text is removed.

## Scope

### In Scope
- The gate hook, the `budget:` config section with defaults, the plan and build changes, two builder agents
  and routing, tests on transcript fixtures

### Out of Scope
- Cost, turn or time caps: shown in the dash, never enforced (decision 43)
- Editing caps in a UI (063)

## Impact

- **Size:** architectural — a new enforcement hook and config others depend on (063's caps)
- **Files affected:** ~12
- **Complexity:** large
- **Risk:** high. A wrong gate stops every subagent. It fails open, and a bad config falls back to the defaults.

Size waiver: one enforcement hook, the `specclaw-budget` CLI that 063 calls as a fixed contract, and the docs and
skill text that explain them (about 680 counted lines, a third of them docs). The hook is unusable without the role
table and config reader it shares with the CLI, and 063 is being built against this CLI in parallel, so a split would
ship either a gate nobody can configure or a contract with nothing behind it.

## Open Questions

- Should the gate ship `off` by default until a project opts in, given it is unproven outside TBML?
- Port TBML's `dl-gate.py` (Python) or write it in TypeScript beside the mod?

---

**To proceed:** Review this proposal and approve to begin planning.
