# Spec: Spec Author Agent

**Change:** spec-author-agent
**Created:** 2026-05-24
**Status:** 🟡 Draft

## Overview

Add a conversational subagent `spec-author` and a standalone skill `/specclaw:author-spec` that walk a user through `templates/spec.md` section by section to produce a detailed, high-quality spec. `/specclaw:plan` gains an opt-in `--author-spec` flag that delegates the spec step to this agent and pauses for approval before generating `design.md` and `tasks.md`. Default `/specclaw:plan` behavior — and therefore `/specclaw:auto` — is unchanged.

## Requirements

### Functional Requirements

- **FR1** — Ship a new subagent definition file at `plugins/specclaw/agents/spec-author.md` with frontmatter (`name`, `description`, `tools`, `model`) and a system prompt that walks `templates/spec.md` section by section.
- **FR2** — The agent's dialogue covers, in order: Overview → Functional Requirements → Non-Functional Requirements → Acceptance Criteria → Edge Cases → Dependencies → Notes. It moves to the next section only after the user confirms the current one (or explicitly says "skip").
- **FR3** — For each section, the agent asks ≥1 clarifying question grounded in the change's `proposal.md`; it does **not** invent requirements silently when the proposal is ambiguous (per Karpathy Rule 1).
- **FR3a** — The agent's system prompt names and uses recognized brainstorming/challenge techniques, applied where each fits best:
  - **5 Whys** — drill from stated solution to root problem (used in Overview / Problem framing).
  - **Jobs-to-be-Done** — frame functional requirements as "When [situation], I want to [motivation], so I can [outcome]" (used in FRs).
  - **Inversion** — "what would make this spec fail / be useless?" (used to surface NFRs).
  - **Pre-mortem** — "imagine we shipped this and it broke — what broke?" (used to surface Edge Cases).
  - **MoSCoW** — Must / Should / Could / Won't, used to challenge scope creep when the user proposes additions.
  - **Concrete-example probe** — ask for a worked example whenever the user gives an abstract requirement.
  The agent picks the technique appropriate to the section, does not robotically apply all of them, and explicitly names the technique to the user (e.g. "Let's do 5 Whys on this — why do you need…").
- **FR3b** — The agent challenges (does not just accept) requirements that look speculative, vague, or untestable. Acceptance criteria must be observable; if the user proposes "system should be fast", the agent pushes for a measurable threshold.
- **FR4** — On completion, the agent writes the final spec to `.specclaw/changes/<change>/spec.md` using `$CLAUDE_PLUGIN_ROOT/templates/spec.md` as the scaffold.
- **FR5** — Ship a new skill `plugins/specclaw/skills/author-spec/SKILL.md` invokable as `/specclaw:author-spec <change>`. It validates that `proposal.md` exists, then invokes the `spec-author` agent for `<change>`. If `spec.md` already exists it asks for confirmation before overwriting.
- **FR6** — Modify `plugins/specclaw/skills/plan/SKILL.md` to detect the `--author-spec` flag in ARGUMENTS. When present, delegate the spec step to `spec-author`, then **pause** and require explicit user approval before generating `design.md` and `tasks.md`.
- **FR7** — Without `--author-spec`, `/specclaw:plan` behaves exactly as it does today (single-shot generation of all three files).
- **FR8** — Update `README.md` (repo root) `Commands` table and brief workflow description to document `/specclaw:author-spec` and the `--author-spec` flag.

### Non-Functional Requirements

- **NFR1** — The agent's system prompt follows the existing plugin convention used by other skills (Markdown with a brief description and numbered steps). No new dependencies.
- **NFR2** — The agent must obey the existing guardrails in `references/agent-guardrails.md` (Rules 1 & 2 in particular: surface assumptions, no speculative additions).
- **NFR3** — `/specclaw:auto` and any non-interactive invocation of `/specclaw:plan` must remain non-interactive — verified by running `/specclaw:plan` without the flag and observing no agent dialogue.
- **NFR4** — Agent and skill files must be plain Markdown with valid YAML frontmatter so they're picked up by Claude Code's plugin auto-discovery (no manifest changes required).

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC1** — `plugins/specclaw/agents/spec-author.md` exists with valid frontmatter and a system prompt that names each section of `templates/spec.md`.
- **AC2** — `plugins/specclaw/skills/author-spec/SKILL.md` exists, is discovered by `/reload-plugins`, and appears as `/specclaw:author-spec` in the skills list.
- **AC3** — Invoking `/specclaw:author-spec spec-author-agent` (the in-flight change itself, as a self-test) opens an interactive dialogue and produces a `spec.md` reflecting the user's answers, written to `.specclaw/changes/spec-author-agent/spec.md`.
- **AC3a** — During the dialogue, the agent explicitly references at least three of the named techniques (5 Whys, JTBD, Inversion, Pre-mortem, MoSCoW, Concrete-example probe) by name and applies them — verified by inspecting the transcript of the self-test run in `verify-report.md`.
- **AC3b** — The agent pushes back on at least one vague/untestable requirement during the self-test (e.g. asks for a measurable threshold when the user says "should be fast" or similar) — recorded in `verify-report.md`.
- **AC4** — Invoking `/specclaw:plan <change> --author-spec` runs the agent for the spec step, **pauses** after writing `spec.md`, and only proceeds to write `design.md` / `tasks.md` after the user types an approval (e.g. "approved", "yes", "go"). On rejection, no `design.md` / `tasks.md` is created.
- **AC5** — Invoking `/specclaw:plan <change>` **without** the flag produces all three files in one pass with no dialogue, matching the pre-change behavior.
- **AC6** — `/specclaw:author-spec` aborts cleanly if `proposal.md` is missing, with a message naming the missing file.
- **AC7** — If `spec.md` already exists when `/specclaw:author-spec` runs, the user is asked to confirm overwrite; declining leaves the existing file untouched.
- **AC8** — `README.md` Commands table lists `/specclaw:author-spec` with a one-line description, and a sentence somewhere in the README mentions the `--author-spec` flag for `/specclaw:plan`.

## Edge Cases

- **EC1** — `proposal.md` missing → `/specclaw:author-spec` fails fast with a clear message; the new skill's first step calls `specclaw-validate-change .specclaw <change> plan` (the existing validator already enforces this).
- **EC2** — Existing `spec.md` → prompt-to-overwrite, default to "no". Same behavior whether the agent is invoked standalone or via `plan --author-spec`.
- **EC3** — User abandons mid-dialogue → no partial `spec.md` is written; the agent only writes on successful completion of the final section.
- **EC4** — Flag passed in an unexpected position (e.g. `/specclaw:plan --author-spec my-change` vs `/specclaw:plan my-change --author-spec`) → detection is positional-agnostic (substring match on `--author-spec` in ARGUMENTS).
- **EC5** — `/specclaw:auto` happens to advance a change whose proposal is ambiguous → because `auto` calls `plan` without the flag, the existing non-interactive behavior is preserved (no regression).
- **EC6** — User approves `spec.md` but the subsequent `design.md` / `tasks.md` generation fails → the partial state (spec only) is acceptable; the user can rerun `/specclaw:plan <change>` (without the flag) to regenerate the rest.

## Dependencies

- Existing plugin scaffolding: `plugins/specclaw/skills/plan/SKILL.md`, `templates/spec.md`, `references/agent-guardrails.md`, `bin/specclaw-validate-change`.
- Claude Code plugin agent/skill discovery (no SDK changes assumed).
- No new external libraries, binaries, or config keys.

## Notes

- The agent is intentionally additive — the default `/specclaw:plan` flow is untouched so existing automation (`/specclaw:auto`, scheduled runs) is not affected.
- A natural follow-up (out of scope) would be peer agents `design-author` and `tasks-author` that the user can mix-and-match into `/specclaw:plan`.
- Self-test: running `/specclaw:author-spec spec-author-agent` after merging will produce a richer `spec.md` for this very change — a useful smoke test.
