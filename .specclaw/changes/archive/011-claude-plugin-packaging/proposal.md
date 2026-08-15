# Proposal: Package specclaw as an installable Claude Code plugin

**Created:** 2026-05-15
**Status:** 🟡 Draft

## Problem

specclaw currently lives at `skill/` in this repo with one monolithic `SKILL.md` documenting every command (`specclaw init`, `specclaw propose`, `specclaw plan`, `specclaw build`, `specclaw verify`, `specclaw pr`, `specclaw auth ...`). To use it in another project, a user has to manually copy `skill/` into that project — exactly the mistake commit `e62b91f` tried to "fix" by committing a stale snapshot into `.claude/skills/specclaw/`, which then drifted and had to be cleaned up.

The framework is mature (9 completed changes; full propose → plan → build → verify → archive lifecycle) but has no clean install story. It can't be installed, updated, or versioned through Claude Code's native plugin mechanism.

## Proposed Solution

Restructure the repo into a **multi-plugin marketplace** named `chan4lk`, with `specclaw` as its first plugin. Future plugins by the same owner ship under `plugins/<new-name>/` in this same repo — users only ever register one marketplace.

```
/plugin marketplace add chan4lk/specclaw
/plugin install specclaw@chan4lk
```

Three structural shifts driven by best practices:

1. **Manifest at `.claude-plugin/plugin.json`** (the only file in `.claude-plugin/`). All other directories live at the plugin root.
2. **Decompose the monolithic `SKILL.md` into one skill per verb** under `skills/`. Each becomes a namespaced, model-invokable command:
   - `skills/init/SKILL.md` → `/specclaw:init`
   - `skills/propose/SKILL.md` → `/specclaw:propose`
   - `skills/plan/SKILL.md` → `/specclaw:plan`
   - `skills/build/SKILL.md` → `/specclaw:build`
   - `skills/verify/SKILL.md` → `/specclaw:verify`
   - `skills/pr/SKILL.md` → `/specclaw:pr`
   - `skills/auth-azdo/SKILL.md`, `skills/auth-jira/SKILL.md`, `skills/issue/SKILL.md`
   - Each skill has a focused `description:` so Claude picks the right one from natural-language triggers.
3. **Scripts move to `bin/`** so they're added to the Bash `PATH` automatically when the plugin is enabled. `bash skill/scripts/build.sh .specclaw <change>` becomes `specclaw-build .specclaw <change>` — cleaner, and skills no longer encode an internal path.

The plugin name is `specclaw`, giving namespace `/specclaw:*`. Version pinned in `plugin.json` (semver) so updates are deterministic rather than per-commit.

## Scope

### In Scope
- `.claude-plugin/plugin.json` — name, version (`0.1.0`), description, author, repository, license
- `.claude-plugin/marketplace.json` — repo doubles as its own single-plugin marketplace
- Restructure `skill/` → plugin-root layout:
  - `skills/<verb>/SKILL.md` (one per verb, distilled from current monolithic SKILL.md)
  - `bin/specclaw-*` (renamed from `skill/scripts/*.sh`, made executable, accept same args)
  - `references/` (existing reference docs, moved to plugin root)
  - `templates/` (existing templates, moved to plugin root) — referenced by skills via `${CLAUDE_PLUGIN_ROOT}/templates/...` or equivalent
- Update every script that currently does `bash skill/scripts/X.sh` to use the on-PATH binary
- README: install instructions (`/plugin marketplace add ...` → `/plugin install ...`), quickstart, link to existing docs
- CHANGELOG entry for `0.1.0`
- Delete top-level `skill/` after migration (single source of truth)

### Out of Scope
- Submission to the official Anthropic plugin marketplace (separate follow-up — needs the in-app form)
- Hooks, agents, MCP servers, LSP, monitors (none of those exist today; adding them is a separate change)
- A `settings.json` default-agent override (specclaw shouldn't change the user's main thread)
- IDE extensions or web installer
- Migration tooling for users who hand-copied `skill/` somewhere — none known
- Rewriting any lifecycle logic — pure packaging + decomposition
- Multi-language ports

## Impact

- **Files affected:** ~40 (mostly moves/renames; new: `plugin.json`, `marketplace.json`, ~9 per-verb `SKILL.md`, README install section, CHANGELOG)
- **Complexity:** medium — splitting the monolithic SKILL.md cleanly is the main thinking task; the rest is mechanical reorg
- **Risk:** low-medium — no lifecycle behavior changes, but per-verb skill descriptions need to be sharp enough that Claude routes to the right skill without conflict

## Decisions

1. **Plugin operates on the guest repo, not its own install location.** Plugin scripts resolve plugin-internal resources (templates, references) via `$CLAUDE_PLUGIN_ROOT` (with a `BASH_SOURCE`-derived fallback for `--plugin-dir` dev mode), and operate on the **host repo's** current working directory for `.specclaw/` state. The plugin never reads or writes `.specclaw/` inside its own install path.
2. **Skill descriptions reviewed together during planning.** All 9 per-verb `SKILL.md` `description:` fields will be drafted in one pass during `specclaw plan` so we can read them side-by-side and confirm Claude can route correctly (no overlap between "propose" and "plan", etc.).
3. **Self-hosted single-plugin marketplace via `.claude-plugin/marketplace.json`.** Confirmed approach. Schema verified during planning.
4. **`disable-model-invocation: true` on every skill by default.** specclaw is a deliberate workflow — Claude should never trigger `/specclaw:build` etc. spontaneously. User invokes explicitly via slash command. Can be opt-in to model invocation later for individual verbs if user feedback wants it.
5. **Dogfooding is best-effort.** This repo's own `.specclaw/changes/` should keep working post-migration since the plugin reads from the host CWD — but if any tradeoff arises, plugin delivery wins over dogfooding.

---

**Approved 2026-05-15.** Proceeding to `specclaw plan`.
