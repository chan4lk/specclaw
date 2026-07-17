---
layout: default
title: SpecClaw — Spec-driven development for Claude Code
---

# 🦞 SpecClaw

**Spec-driven development for Claude Code.** Just say _"I have a proposal"_ — SpecClaw is a Claude Code plugin that turns a plain-English idea into merged, production-ready code through an automated **propose → plan → build → verify → pr** lifecycle. Every change gets a paper trail: proposal → spec → design → ordered task list → verified PR.

[View on GitHub](https://github.com/chan4lk/specclaw){: .btn .btn-primary}
[Install instructions](#installation){: .btn}
[Commands](#commands){: .btn}

---

## What it does

SpecClaw manages the full lifecycle of a code change inside Claude Code:

1. **`/specclaw:propose "<idea>"`** — drafts a structured proposal (problem, solution, scope, impact, open questions).
2. **`/specclaw:plan <change>`** — generates `spec.md`, `design.md`, and an ordered `tasks.md` from the approved proposal.
3. **`/specclaw:build <change>`** — executes tasks wave-by-wave, committing each one, logging errors and learnings.
4. **`/specclaw:verify <change>`** — runs the configured test/lint/build commands, evaluates against acceptance criteria, writes `verify-report.md`.
5. **`/specclaw:pr <change>`** — opens a GitHub PR (or `/specclaw:pr-azdo` for Azure DevOps) using the spec + verify report as the body.

Optional integrations: GitHub Issues sync, Azure DevOps PRs, Azure Boards Work Items, Jira issues.

## Installation

Requires [Claude Code](https://claude.com/claude-code) v2.1 or later.

```text
/plugin marketplace add chan4lk/specclaw
/plugin install specclaw@chan4lk
```

Future plugins by the same owner ship in the same `chan4lk` marketplace — you only register it once.

## Quickstart

In any project:

```text
> /specclaw:init
  Initializes .specclaw/ in the current project.

> /specclaw:propose "add dark mode support"
  Drafts .specclaw/changes/add-dark-mode/proposal.md.

> /specclaw:plan add-dark-mode
  Generates spec.md, design.md, tasks.md.

> /specclaw:build add-dark-mode
  Executes tasks wave-by-wave, committing each.

> /specclaw:verify add-dark-mode
  Validates implementation against the spec.

> /specclaw:pr add-dark-mode
  Opens the PR.
```

## Why SpecClaw?

AI coding agents are powerful but lose context fast. SpecClaw gives every change durable structure:

- **Proposal** — why this matters, what's in/out of scope
- **Spec** — functional & non-functional requirements, acceptance criteria, edge cases
- **Design** — technical approach, file changes map, key decisions, risks
- **Tasks** — grouped into parallelizable waves with explicit dependencies
- **Verify report** — evidence the implementation meets the spec
- **Cross-change learnings & patterns** — recurring issues become prevention rules

State lives in `.specclaw/` in your project. The plugin operates on your CWD; nothing is hidden inside the install.

## Commands

All commands are namespaced under `/specclaw:`. Most are model-invokable — Claude will route conversationally (e.g. "i have a proposal" fires `/specclaw:propose`). Auth setup commands (`/specclaw:auth-azdo`, `/specclaw:auth-jira`) stay explicit-only because they handle credentials.

| Command | Purpose |
|---------|---------|
| `/specclaw:init` | Initialize `.specclaw/` in the current project |
| `/specclaw:propose "<idea>"` | Draft a new change proposal |
| `/specclaw:plan <change>` | Generate spec + design + tasks |
| `/specclaw:build <change>` | Execute tasks wave-by-wave |
| `/specclaw:learn <change> "..."` | Record a spec gap, design miss, or pattern |
| `/specclaw:patterns` | Inspect the cross-change pattern registry |
| `/specclaw:verify <change>` | Validate implementation against spec |
| `/specclaw:pr <change>` | Open a GitHub PR |
| `/specclaw:pr-azdo <change>` | Open an Azure DevOps PR |
| `/specclaw:auth-azdo` | One-time Azure DevOps credentials setup |
| `/specclaw:auth-jira` | One-time Jira credentials setup |
| `/specclaw:issue <change>` | Create a Jira issue from a proposal |
| `/specclaw:azdo-issue <change>` | Create an Azure Boards Work Item from a proposal |
| `/specclaw:status` | Show the project dashboard |
| `/specclaw:archive <change>` | Archive a completed change |
| `/specclaw:auto` | Advance the queue of active changes autonomously |

## Project structure

When initialized in a project, SpecClaw creates:

```text
.specclaw/
├── config.yaml          # Project config (models, git strategy, integrations)
├── STATUS.md            # Cross-change dashboard
├── patterns.md          # Recurring pattern registry
└── changes/
    └── <change-name>/
        ├── proposal.md      # Problem + solution + scope
        ├── spec.md          # Requirements + acceptance criteria
        ├── design.md        # Technical approach + file map
        ├── tasks.md         # Ordered tasks with status markers
        ├── status.md        # Per-change progress tracking
        ├── errors.md        # Build error journal
        ├── learnings.md     # Spec gaps, patterns, insights
        └── verify-report.md # Verification results
```

## Plugin architecture

This repo doubles as the `chan4lk` plugin marketplace. The specclaw plugin lives at `plugins/specclaw/`:

```text
specclaw/
├── .claude-plugin/marketplace.json   ← chan4lk marketplace catalog
└── plugins/
    └── specclaw/
        ├── .claude-plugin/plugin.json
        ├── skills/<verb>/SKILL.md    ← 15 namespaced skills
        ├── bin/specclaw-*            ← 18 lifecycle scripts on $PATH
        ├── templates/                ← proposal.md, spec.md, etc.
        └── references/               ← agent prompts, build engine docs
```

Scripts resolve plugin-internal resources via `$CLAUDE_PLUGIN_ROOT` and operate on the host repo's current working directory for `.specclaw/` state.

## License & Privacy

MIT — see [LICENSE](https://github.com/chan4lk/specclaw/blob/main/LICENSE).

The plugin does not collect, store, or transmit user data. See [Privacy Policy](./privacy.html) for details.

## Contributing

PRs welcome. See [CONTRIBUTING.md](https://github.com/chan4lk/specclaw/blob/main/CONTRIBUTING.md).

---

<sub>Made with 🦞 by <a href="https://github.com/chan4lk">@chan4lk</a>. SpecClaw is the first plugin in the <code>chan4lk</code> Claude Code marketplace.</sub>
