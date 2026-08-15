# Design: Package specclaw as an installable Claude Code plugin

**Change:** claude-plugin-packaging
**Created:** 2026-05-15

## Technical Approach

This is a packaging change, not a behavioral one. The execution is a mechanical reorganization:

1. **Add manifests.** Write `.claude-plugin/plugin.json` (plugin identity) and `.claude-plugin/marketplace.json` (single-plugin marketplace pointing at `.`).
2. **Split the monolithic SKILL.md.** Carve `skill/SKILL.md` into 15 per-verb `skills/<verb>/SKILL.md` files. Each one gets the original verb's section, rewritten to (a) drop the `### `specclaw foo`` heading, (b) replace `bash skill/scripts/X.sh` with `specclaw-X`, (c) gain YAML frontmatter with description + `disable-model-invocation: true`.
3. **Move scripts to `bin/`.** Rename `skill/scripts/<name>.sh` → `bin/specclaw-<name>` (drop `.sh`, prefix with `specclaw-`). Mark executable. Patch each script's resource-resolution code to use `$CLAUDE_PLUGIN_ROOT`.
4. **Move resources.** `skill/templates/` → `templates/` at plugin root. `skill/references/` → `references/` at plugin root.
5. **Delete `skill/`.**
6. **Update README and add CHANGELOG.**
7. **Validate end-to-end** by installing the plugin into a throwaway sibling directory via `--plugin-dir .` and running through propose → plan.

The plugin scripts already separate plugin-internal data (templates, the script itself) from host state (`.specclaw/` in CWD). The migration just changes *where* the plugin-internal data lives — from `skill/...` relative to repo root to `$CLAUDE_PLUGIN_ROOT/...` relative to the plugin install root.

## Architecture

The repo doubles as the **`chan4lk` marketplace** — extensible to host more plugins later. Pattern A (nested) layout: plugins live under `plugins/<plugin-name>/`. Adding a future plugin is just `mkdir plugins/<new-plugin>/` plus a new entry in `marketplace.json`.

```
specclaw/                                  ← repo root = marketplace root (chan4lk)
├── .claude-plugin/
│   └── marketplace.json                   ← marketplace catalog: name "chan4lk"
├── plugins/
│   └── specclaw/                          ← plugin root
│       ├── .claude-plugin/
│       │   └── plugin.json                ← plugin manifest: name "specclaw", v0.1.0
│       ├── skills/
│       │   ├── init/SKILL.md              ← /specclaw:init
│       │   ├── propose/SKILL.md           ← /specclaw:propose
│       │   ├── plan/SKILL.md              ← /specclaw:plan
│       │   ├── build/SKILL.md             ← /specclaw:build
│       │   ├── learn/SKILL.md             ← /specclaw:learn
│       │   ├── patterns/SKILL.md          ← /specclaw:patterns
│       │   ├── verify/SKILL.md            ← /specclaw:verify
│       │   ├── pr/SKILL.md                ← /specclaw:pr (GitHub)
│       │   ├── pr-azdo/SKILL.md           ← /specclaw:pr-azdo
│       │   ├── auth-azdo/SKILL.md         ← /specclaw:auth-azdo
│       │   ├── auth-jira/SKILL.md         ← /specclaw:auth-jira
│       │   ├── issue/SKILL.md             ← /specclaw:issue (Jira)
│       │   ├── status/SKILL.md            ← /specclaw:status
│       │   ├── archive/SKILL.md           ← /specclaw:archive
│       │   └── auto/SKILL.md              ← /specclaw:auto
│       ├── bin/                           ← added to $PATH when plugin enabled
│       │   ├── specclaw-init
│       │   ├── specclaw-build
│       │   ├── specclaw-verify
│       │   ├── specclaw-pr
│       │   ├── specclaw-azdo-pr
│       │   ├── specclaw-auth-azdo
│       │   ├── specclaw-auth-jira
│       │   ├── specclaw-jira-issue
│       │   ├── specclaw-gh-sync
│       │   ├── specclaw-validate-change
│       │   ├── specclaw-build-context
│       │   ├── specclaw-verify-context
│       │   ├── specclaw-detect-patterns
│       │   ├── specclaw-parse-tasks
│       │   ├── specclaw-update-status
│       │   ├── specclaw-update-task-status
│       │   ├── specclaw-log-error
│       │   └── specclaw-log-learning
│       ├── templates/                     ← config.yaml, proposal.md, spec.md, etc.
│       └── references/                    ← agent-prompts.md, build-engine.md, etc.
├── README.md                              ← updated with install section
├── CHANGELOG.md                           ← new, [0.1.0] entry
├── LICENSE
├── CONTRIBUTING.md
├── CLAUDE.md
└── .specclaw/                             ← dogfood state at repo root (host CWD)
```

**Future growth:**
```
plugins/
├── specclaw/                              ← this change
└── <next-plugin>/                         ← add here, plus marketplace.json entry
```

## File Changes Map

| File | Action | Description |
|------|--------|-------------|
| `.claude-plugin/marketplace.json` | **add** | Marketplace `chan4lk`: lists `specclaw` plugin sourced from `./plugins/specclaw` |
| `plugins/specclaw/.claude-plugin/plugin.json` | **add** | Plugin manifest: name `specclaw`, v0.1.0, description, author, repository, license |
| `plugins/specclaw/skills/<verb>/SKILL.md` × 15 | **add** | One per verb; carved from `skill/SKILL.md` |
| `plugins/specclaw/bin/specclaw-*` × 18 | **add** | Moved+renamed from `skill/scripts/*.sh`; resource paths via `$CLAUDE_PLUGIN_ROOT` |
| `plugins/specclaw/templates/*` | **move** | From `skill/templates/` |
| `plugins/specclaw/references/*` | **move** | From `skill/references/` |
| `skill/` | **delete** | After all content migrated |
| `README.md` | **modify** | Add `## Installation` section with marketplace + install commands |
| `CHANGELOG.md` | **add** | New file; `[0.1.0]` entry |
| `.gitignore` | **modify** (maybe) | If anything plugin-cache-related needs ignoring |

## Data Model Changes

None. The host repo's `.specclaw/` schema is untouched.

## API Changes

**Invocation surface changes:**

| Before | After |
|--------|-------|
| `bash skill/scripts/build.sh .specclaw <change>` | `specclaw-build .specclaw <change>` |
| `bash skill/scripts/validate-change.sh .specclaw <change> plan` | `specclaw-validate-change .specclaw <change> plan` |
| _(conversational)_ "specclaw propose ..." | `/specclaw:propose ...` (explicit) or conversational still triggers the right SKILL.md |

The conversational interface is preserved by virtue of skill descriptions — Claude reads the skill set and matches user intent to a skill. But because `disable-model-invocation: true`, the user must explicitly invoke the slash command. This is the intended trade-off per the user's decision.

## Key Decisions

**KD1 — Repo root is the marketplace root; plugins nested under `plugins/`.** Pattern A — repo doubles as the multi-plugin marketplace `chan4lk`. `.claude-plugin/marketplace.json` at repo root lists plugins; each plugin lives at `plugins/<name>/` with its own `.claude-plugin/plugin.json`. Chosen so future plugins by the same owner go in the same marketplace under their own subdirectories — users only register one marketplace (`chan4lk/specclaw`) to get access to all of them.

**KD2 — `disable-model-invocation: true` on every skill.** Per user decision. specclaw is deliberate; Claude shouldn't auto-fire `/specclaw:build` because someone said "let's build the feature". User runs the slash command explicitly.

**KD3 — `bin/` over `commands/`.** Plugin scripts live in `bin/` (added to `$PATH`) rather than `commands/` (which is for the legacy flat-markdown skills approach). `bin/` keeps the scripts callable from anywhere as plain executables.

**KD4 — `$CLAUDE_PLUGIN_ROOT` with `BASH_SOURCE` fallback.** Standard idiom for plugin-internal resource resolution:
   ```bash
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
   ```
   Works in both installed mode and `--plugin-dir` dev mode.

**KD5 — Marketplace name = `chan4lk`.** User runs `/plugin marketplace add chan4lk/specclaw` (the repo URL) then `/plugin install specclaw@chan4lk` (plugin `specclaw` from marketplace `chan4lk`). Marketplace and plugin namespaces are now cleanly separate; future plugins added under `plugins/<name>/` show up as `<name>@chan4lk`. The repo URL slug being `specclaw` is a historical artifact — it could be renamed to `chan4lk/plugins` later without breaking anything since the marketplace name is what users reference at install time.

**KD6 — Skill descriptions (DRAFT — review during build).**

| Skill | Description |
|-------|-------------|
| init | Initialize specclaw in this project. Creates `.specclaw/` directory, generates `config.yaml`, sets up project metadata. Run once per project before any other specclaw command. |
| propose | Draft a new change proposal. Creates `.specclaw/changes/<name>/proposal.md` with problem statement, solution, scope, impact, and open questions. The first step in the propose → plan → build → verify → pr lifecycle. |
| plan | Generate spec, design, and ordered task list for an approved proposal. Reads `proposal.md`, analyzes the codebase, writes `spec.md`, `design.md`, `tasks.md`. Run after propose, before build. |
| build | Implement the planned tasks by spawning coding agents. Reads `tasks.md`, executes tasks in wave order, commits each, logs errors and learnings. The longest-running phase. |
| learn | Record an insight, spec gap, or pattern observed during build. Appends to `.specclaw/changes/<name>/learnings.md`. Use mid-build to capture knowledge before it's lost. |
| patterns | Inspect the cross-change pattern registry (`.specclaw/patterns.md`). Use to see recurring approaches before planning a new change. |
| verify | Run the verification suite for a built change. Executes build/test/lint commands, writes `verify-report.md` with pass/fail. Required before `pr`. |
| pr | Create a GitHub pull request for a verified change. Reads `verify-report.md`, opens PR with title from proposal and body from spec, enforces test policy. Requires `gh` CLI. |
| pr-azdo | Create an Azure DevOps pull request. Same as `pr` but targets ADO; requires `specclaw:auth-azdo` first. |
| auth-azdo | Interactive setup for Azure DevOps authentication. Prompts for org/project/repo, validates PAT, saves credentials to gitignored `.specclaw/.env`. Run once per project before `pr-azdo`. |
| auth-jira | Interactive setup for Jira authentication. Prompts for domain/email/project, validates API token, saves credentials. Run once before `issue`. |
| issue | Create a Jira issue for a proposed change. Mirrors GitHub Issues sync but for Jira-based teams. Requires `auth-jira` first. |
| status | Show the project's specclaw dashboard: active changes, completed changes, blocked work. Reads `.specclaw/STATUS.md`. |
| archive | Move a completed change to `.specclaw/changes/archive/`. Use after a change is merged. |
| auto | Run the propose → plan → build → verify loop autonomously for a queue of changes. Advanced; requires config under `automation:`. |

These will be re-reviewed when the build agent writes each `SKILL.md` to ensure they remain disjoint.

**KD7 — Bash 3.2 compatibility.** Reaffirmed; no changes to script style.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `$CLAUDE_PLUGIN_ROOT` not set in dev mode | Medium | Use `${VAR:-fallback}` idiom; test with `--plugin-dir .` |
| Two skills with overlapping descriptions cause Claude to route incorrectly | Medium | Review descriptions table together; test with sample utterances in a sibling repo |
| Existing user with cloned `skill/` breaks on update | Low | Note in CHANGELOG. No known external users. |
| Path-encoded references inside scripts I miss in the audit | Medium | `grep -rn "skill/" bin/ skills/` after migration; CI-style check in `verify` |
| `gh-sync.sh` invokes other scripts by path | Medium | Audit all `source` and `bash` invocations during build; rewrite to use `$PATH` lookup or `$CLAUDE_PLUGIN_ROOT/bin/` |
| Plugin can't be installed (Claude Code <2.1) | Low | Document minimum version in README |
| Slash command name collisions (e.g. another plugin uses `init`) | Low | Namespacing (`/specclaw:init`) prevents conflict by design |
