# Design: Spec Author Agent

**Change:** spec-author-agent
**Created:** 2026-05-24

## Technical Approach

Two new files, one edited file, one doc update. No new binaries, no config-schema changes, no manifest edits — Claude Code auto-discovers agents and skills under `plugins/specclaw/agents/**` and `plugins/specclaw/skills/**`.

Flow:

1. `/specclaw:author-spec <change>` (standalone) → skill validates prerequisites → invokes `spec-author` agent with the change name → agent reads `proposal.md`, walks `templates/spec.md` section-by-section via interactive dialogue → writes `spec.md`.
2. `/specclaw:plan <change> --author-spec` → existing plan skill detects the flag → does steps 1-3 as today (validate, read proposal, analyze code) → delegates spec step to `spec-author` → **pauses for explicit approval** → continues to generate `design.md` and `tasks.md`.
3. `/specclaw:plan <change>` (no flag) → unchanged, single-shot generation.

The "pause for approval" is realized as a literal instruction in the plan skill prompt — Claude stops emitting tool calls and waits for the user's next message. This matches how `/specclaw:propose` already requires approval before `/specclaw:plan` runs.

## Architecture

```text
plugins/specclaw/
├── agents/                          ← NEW directory
│   └── spec-author.md               ← NEW: subagent definition
├── skills/
│   ├── author-spec/                 ← NEW directory
│   │   └── SKILL.md                 ← NEW: /specclaw:author-spec
│   └── plan/
│       └── SKILL.md                 ← EDIT: detect --author-spec flag
└── templates/spec.md                ← UNCHANGED (consumed by agent)
README.md                            ← EDIT: document new skill + flag
```

Agent invocation uses the standard Claude Code `Agent` tool with `subagent_type: "spec-author"`. The agent receives the change name and is instructed to read `.specclaw/changes/<change>/proposal.md` itself and write `.specclaw/changes/<change>/spec.md` itself — keeping the skill prompts thin.

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `plugins/specclaw/agents/spec-author.md` | CREATE | Agent frontmatter (`name`, `description`, `tools: [Read, Write, Bash]`, `model: opus`) + system prompt that walks `templates/spec.md` section-by-section, asks ≥1 question per section, writes final `spec.md`. |
| `plugins/specclaw/skills/author-spec/SKILL.md` | CREATE | Skill frontmatter + body. Runs `specclaw-ensure-init`, validates proposal exists via `specclaw-validate-change`, checks for existing `spec.md` (asks to overwrite), invokes `Agent(subagent_type=spec-author, ...)`, updates status, syncs to GitHub/Azure if enabled. |
| `plugins/specclaw/skills/plan/SKILL.md` | EDIT | Insert a conditional block: if ARGUMENTS contains `--author-spec`, delegate the spec step to the `spec-author` agent and pause for explicit user approval before steps that generate `design.md` / `tasks.md`. Strip the flag from the change name when parsing. |
| `README.md` | EDIT | Add `/specclaw:author-spec <change>` row to Commands table; one-sentence mention of the `--author-spec` flag for `/specclaw:plan`. |

## Data Model Changes

None. No new fields in `config.yaml`, no new `.specclaw/` artifacts, no changes to existing templates.

## API Changes

None internal. Two new user-facing surfaces:

- New slash command `/specclaw:author-spec <change>`.
- New flag `--author-spec` accepted by `/specclaw:plan <change>`.

## Key Decisions

- **Agent vs inline skill prompt.** A dedicated agent isolates the multi-turn dialogue from the main thread's tool history and lets us pin the planning model (`anthropic/claude-opus-4-6`) per `config.yaml`. An inline skill prompt would couple the dialogue to whatever model the main loop is on.
- **Opt-in flag, not default.** Keeps `/specclaw:auto` and existing scripted invocations of `/specclaw:plan` non-interactive — critical for the autopilot workflow.
- **Section-by-section, not whole-spec-at-once.** Karpathy Rule 1 (Think Before Coding) explicitly calls out "if multiple interpretations exist, present them". Section-by-section enforces this by structurally giving the user a checkpoint per section.
- **Named technique catalog over generic "ask questions".** The agent prompt embeds a small table mapping spec sections → technique (5 Whys for Problem/Overview, JTBD for FRs, Inversion for NFRs, Pre-mortem for Edge Cases, MoSCoW for scope challenges, Concrete-example probe for any abstract claim). The agent is instructed to name the technique aloud ("Let's do 5 Whys here…") so the user understands the move. This trades a longer system prompt for higher-quality, less-generic dialogue and is the core differentiator from a plain "ask clarifying questions" agent.
- **Challenge mode is mandatory, not optional.** The agent is instructed to push back on vague or untestable requirements (e.g. "fast", "easy", "secure") and require an observable threshold before writing them into `spec.md`. This implements FR3b and prevents the spec from inheriting the proposal's ambiguity.
- **Skill name `/specclaw:author-spec` (with hyphen).** Matches existing multi-word skill names in the plugin (`auth-azdo`, `pr-azdo`, `azdo-issue`). Consistent.
- **No new manifest entry.** Claude Code auto-discovers under `agents/` and `skills/`. Verified by inspecting `plugin.json` — it only declares package metadata, not skill/agent lists.

## Risks & Mitigations

- **Risk: plugin auto-discovery doesn't find the new `agents/` directory** (no existing agents in this plugin, so unproven path).
  - *Mitigation:* AC2 explicitly tests that `/reload-plugins` surfaces the new skill, and the build task verifies the agent is invokable. If discovery fails, fall back to inlining the system prompt directly in the skill (cheap rewrite, no API change for users).
- **Risk: the `--author-spec` flag detection is brittle** (e.g. user passes a change name that contains the literal string).
  - *Mitigation:* match the flag as a whitespace-delimited token (`\b--author-spec\b`), not a substring. Change names are slugified, so collision is essentially impossible.
- **Risk: agent writes a partial `spec.md` if the dialogue is interrupted.**
  - *Mitigation:* the agent only calls `Write` once, at the end, after the last section is confirmed. Documented in the agent prompt.
- **Risk: pause-for-approval is just a prompt instruction — Claude might continue anyway.**
  - *Mitigation:* phrase the instruction with the same explicit STOP wording used in `/specclaw:propose` ("Do not proceed to `/specclaw:plan` until the user has approved"). That wording is observed to hold reliably in the existing flow.
