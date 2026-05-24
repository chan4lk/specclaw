# 🦞 SpecClaw

**Spec-driven development for Claude Code.**

SpecClaw is a Claude Code plugin that manages the full lifecycle of a code change: propose → plan → build → verify → pr. It writes structured proposals, specs, designs, and ordered task lists into your project, then drives implementation through the lifecycle with full traceability from requirement to merged PR.

## Why SpecClaw?

AI coding agents are powerful but lose context fast. SpecClaw gives every change a paper trail:

- **`proposal.md`** — why this change matters
- **`spec.md`** — requirements + acceptance criteria
- **`design.md`** — technical approach, file map, key decisions, risks
- **`tasks.md`** — ordered tasks, grouped into parallelizable waves
- **`verify-report.md`** — evidence the implementation meets the spec
- **GitHub / Azure DevOps / Jira sync** — keep external trackers up to date

Each change lives in `.specclaw/changes/<name>/` in your repo. The plugin operates on your project's CWD; nothing is hidden inside the plugin install.

## Installation

Requires [Claude Code](https://claude.com/claude-code) v2.1 or later.

```
/plugin marketplace add chan4lk/specclaw
/plugin install specclaw@chan4lk
```

Future plugins by the same owner ship in the same `chan4lk` marketplace — you only register it once.

## Quickstart

```
> /specclaw:init
  Initializes .specclaw/ in the current project, generates config.yaml, creates the dashboard.

> /specclaw:propose "add dark mode support"
  Drafts .specclaw/changes/add-dark-mode/proposal.md for your review.

> /specclaw:plan add-dark-mode
  Generates spec.md, design.md, tasks.md once the proposal is approved.
  Append --author-spec to author spec.md interactively via the spec-author subagent, with an approval gate before design.md / tasks.md.

> /specclaw:build add-dark-mode
  Executes tasks wave-by-wave, committing each.

> /specclaw:verify add-dark-mode
  Runs tests/lint/build, evaluates against acceptance criteria, writes verify-report.md.

> /specclaw:pr add-dark-mode
  Opens a GitHub PR using the spec + verify report as the description.
```

## Project Structure

When initialized in a project, SpecClaw creates:

```
.specclaw/
├── config.yaml          # Project config (models, git strategy, integrations)
├── STATUS.md            # Cross-change dashboard
├── patterns.md          # Recurring pattern registry (cross-change)
└── changes/
    └── <change-name>/
        ├── proposal.md      # Problem + solution + scope
        ├── spec.md          # Requirements + acceptance criteria
        ├── design.md        # Technical approach + file map
        ├── tasks.md         # Ordered tasks with status markers
        ├── status.md        # Per-change progress tracking
        ├── errors.md        # Build error journal (auto-generated on failures)
        ├── learnings.md     # Build learnings (spec gaps, patterns, insights)
        └── verify-report.md # Verification results
```

## Commands

All commands are namespaced under `/specclaw:`. Most are model-invokable — Claude will route conversationally (e.g. "i have a proposal" fires `/specclaw:propose`). Auth setup commands (`/specclaw:auth-azdo`, `/specclaw:auth-jira`) are explicit-only because they handle credentials.

| Command | Purpose |
|---------|---------|
| `/specclaw:init` | Initialize `.specclaw/` in the current project |
| `/specclaw:propose "<idea>"` | Draft a new change proposal |
| `/specclaw:plan <change>` | Generate spec + design + tasks (append `--author-spec` for interactive spec authoring with an approval gate) |
| `/specclaw:author-spec <change>` | Author `spec.md` interactively via the `spec-author` subagent (5 Whys, JTBD, Inversion, Pre-mortem, MoSCoW) |
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

## Configuration

`.specclaw/config.yaml`:

```yaml
version: 1
project:
  name: "my-project"
  description: "Short description"

models:
  planning: "anthropic/claude-opus-4-6"
  coding: "openai/gpt-5.1-codex"
  review: "anthropic/claude-sonnet-4-5"

git:
  strategy: "branch-per-change"   # or "direct", or "worktree-per-change"
  auto_commit: true
  commit_prefix: "specclaw"

github:
  sync: true
  repo: "owner/repo"
  label: "specclaw"

azdo:                              # set via /specclaw:auth-azdo
  org: ""
  project: ""
  repo: ""

jira:                              # set via /specclaw:auth-jira
  domain: ""
  email: ""
  project_key: ""

automation:
  auto_verify: true
  auto_archive: false
  max_tasks_per_run: 5
```

## Workflow

1. **Propose** — draft a proposal, refine it with the user.
2. **Plan** — once approved, generate spec + design + tasks.
3. **Build** — execute the tasks, committing each one. Failures log to `errors.md`; insights log to `learnings.md`.
4. **Verify** — run the configured test/lint/build commands, evaluate against acceptance criteria, write `verify-report.md`.
5. **PR** — open a GitHub PR (or `/specclaw:pr-azdo` for Azure DevOps) using the spec and verify report as the description.
6. **Archive** — after merge, move the change to `.specclaw/changes/archive/`.

## Plugin Architecture

This repo is the `chan4lk` plugin marketplace. The specclaw plugin lives at `plugins/specclaw/` and is the marketplace's first plugin:

```
specclaw/                            ← chan4lk marketplace root
├── .claude-plugin/marketplace.json
└── plugins/
    └── specclaw/
        ├── .claude-plugin/plugin.json
        ├── skills/<verb>/SKILL.md   ← 15 namespaced skills
        ├── bin/specclaw-*           ← lifecycle scripts on $PATH
        ├── templates/               ← proposal.md, spec.md, etc.
        └── references/              ← agent prompts, build engine docs
```

Scripts resolve plugin-internal resources via `$CLAUDE_PLUGIN_ROOT` and operate on the host repo's current working directory for `.specclaw/` state — nothing is written inside the plugin install.

## License

MIT

## Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
