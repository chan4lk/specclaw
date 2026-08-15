# Proposal: Spec Author Agent

**Created:** 2026-05-24
**Status:** 🟡 Draft

## Problem

Today, `/specclaw:plan` generates `spec.md` in a single shot from `proposal.md`. The result is often thin: requirements are inferred from a short proposal without dialogue, edge cases get missed, and acceptance criteria end up vague. Users end up rewriting the spec by hand before `/specclaw:build` is safe to run.

The plugin has 16 skills but **zero agents** under `plugins/specclaw/agents/` — there is no conversational sub-agent dedicated to specification authoring. The `templates/spec.md` scaffold (Overview, Functional Requirements, Non-Functional Requirements, Acceptance Criteria, Edge Cases, Dependencies, Notes) is well-structured but currently filled out by the main loop in passing.

## Proposed Solution

Add a new subagent `spec-author` shipped under `plugins/specclaw/agents/spec-author.md` that:

1. Loads `proposal.md` for a given change.
2. Walks the user through the `spec.md` template **section by section** via Socratic dialogue (one section at a time, asking targeted clarifying questions).
3. Probes for edge cases, ambiguous wording, missing non-functional requirements (performance, security, observability), and dependencies.
4. Writes the resulting detailed `spec.md` to `.specclaw/changes/<change>/spec.md` using `templates/spec.md` as the scaffold.
5. Is callable two ways:
   - **Standalone**: a new `/specclaw:author-spec` skill invokes it for an already-approved proposal.
   - **From `/specclaw:plan --author-spec`**: with the flag, `plan` delegates the `spec.md` step to `spec-author` and **pauses for user approval of `spec.md` before generating `design.md` / `tasks.md`**. Without the flag, `plan` behaves as it does today (non-interactive one-shot), so `/specclaw:auto` is unaffected.

**Interaction style:** blocking Socratic dialogue in the main thread. The flag is the escape hatch for automation.

The agent uses the planning model (`anthropic/claude-opus-4-6` per `config.yaml`) and follows the same guardrails as `references/agent-guardrails.md` (Rule 1: state assumptions, Rule 2: simplicity first).

## Scope

### In Scope
- New file: `plugins/specclaw/agents/spec-author.md` (agent frontmatter + system prompt).
- New skill: `plugins/specclaw/skills/author-spec/SKILL.md` — invokes the agent for a named change.
- Add `--author-spec` flag handling to `plugins/specclaw/skills/plan/SKILL.md` that delegates the spec step to `spec-author` and **pauses for user approval of `spec.md` before generating `design.md` / `tasks.md`**.
- Update plugin manifest (`.claude-plugin/plugin.json` or equivalent) so the agent is discovered.
- Brief docs update in the plugin README about the new agent + `/specclaw:author-spec` skill + `--author-spec` flag.

### Out of Scope
- Changing the `templates/spec.md` shape itself.
- Replacing or rewriting `/specclaw:plan` end-to-end.
- A separate "design author" or "tasks author" agent (could be follow-ups).
- Multi-spec / spec-versioning workflows.

## Impact

- **Files affected:** ~5 (new agent, new skill, plan skill edit, plugin manifest, README) (estimated)
- **Complexity:** small
- **Risk:** low — additive; the existing `/specclaw:plan` flow keeps working even if the agent is bypassed.

## Decisions

1. **Invocation style:** blocking, interactive Socratic dialogue.
2. **`/specclaw:plan` integration:** opt-in via `--author-spec` flag — default behavior unchanged so `/specclaw:auto` stays non-interactive.
3. **Skill name:** `/specclaw:author-spec`.
4. **Approval gate:** when the flag is on, pause after `spec.md` for explicit user approval before generating `design.md` / `tasks.md`.

## Open Questions

_None — all resolved above._

---

**To proceed:** Review this proposal and approve to begin planning.
