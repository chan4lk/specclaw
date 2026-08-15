# Spec: Package specclaw as an installable Claude Code plugin

**Change:** claude-plugin-packaging
**Created:** 2026-05-15
**Status:** 🟡 Draft

## Overview

Restructure this repo so it doubles as the `chan4lk` Claude Code plugin marketplace, with `specclaw` as its first plugin. After this change, any user can install specclaw into any project by running `/plugin marketplace add chan4lk/specclaw` followed by `/plugin install specclaw@chan4lk`, then drive the lifecycle (propose → plan → build → verify → pr) from inside that project via namespaced slash commands like `/specclaw:propose`. Future plugins by the same owner ship under `plugins/<new-name>/` in this same repo and are installable as `<new-name>@chan4lk` — users only ever register one marketplace.

The plugin operates on the **guest repo's** current working directory — the user's `.specclaw/` state lives in their project, never in the plugin install cache. The plugin install path is read-only at runtime aside from the on-PATH binaries it exposes.

## Requirements

### Functional Requirements

**FR1 — Installable as a Claude Code plugin.** The repo contains `plugins/specclaw/.claude-plugin/plugin.json` with name `specclaw`, semver `version`, `description`, `author`, `homepage`, `repository`, and `license` fields populated.

**FR2 — Distributable via a self-hosted multi-plugin marketplace.** The repo contains `.claude-plugin/marketplace.json` at its root with marketplace name `chan4lk`, an owner block, and a `plugins` array. The array lists exactly one plugin (`specclaw`) sourced from `./plugins/specclaw`. After `/plugin marketplace add chan4lk/specclaw`, the user can `/plugin install specclaw@chan4lk` successfully. The structure supports adding future plugins under `plugins/<other-name>/` with corresponding entries.

**FR3 — One skill per lifecycle verb.** Each user-facing verb in the current monolithic `skill/SKILL.md` becomes a separate skill under `plugins/specclaw/skills/<verb>/SKILL.md`. Every skill has YAML frontmatter with `description:` and `disable-model-invocation: true`.

**FR4 — Verbs covered.** The skill set covers all current verbs: `init`, `propose`, `plan`, `build`, `learn`, `patterns`, `verify`, `pr`, `pr-azdo`, `auth-azdo`, `auth-jira`, `issue`, `status`, `archive`, `auto`. Each is invokable as `/specclaw:<verb>` (with hyphens for multi-word).

**FR5 — Scripts on `PATH` via `bin/`.** All lifecycle scripts move to `plugins/specclaw/bin/`, renamed `specclaw-<verb>` (e.g. `specclaw-build`, `specclaw-verify`, `specclaw-validate-change`). They are executable (`chmod +x`) and use a `#!/usr/bin/env bash` shebang. Once the plugin is enabled, these are callable by name from any directory.

**FR6 — Scripts resolve plugin-internal resources via `$CLAUDE_PLUGIN_ROOT`.** Any script that reads templates, references, or other plugin-bundled files resolves them via `${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}`. This works both when installed (env var set) and in `--plugin-dir` dev mode (fallback to script-relative path).

**FR7 — Scripts operate on the host CWD for state.** Every script that reads or writes `.specclaw/` resolves it from the current working directory at invocation time (the host project), never from inside the plugin install. No script writes to its own install path.

**FR8 — Skills delegate to `bin/` scripts.** Each `SKILL.md` body is the procedural instruction set previously embedded in the monolithic SKILL.md for that verb, with script invocations rewritten from `bash skill/scripts/X.sh ...` to the on-PATH form `specclaw-X ...`.

**FR9 — README install section.** The repo README documents the new install path: `/plugin marketplace add ...`, `/plugin install ...`, and a quickstart that runs `/specclaw:init` and `/specclaw:propose` in a fresh project.

**FR10 — CHANGELOG.** A `CHANGELOG.md` at the repo root records `0.1.0` as the first plugin release and lists the structural changes.

**FR11 — Legacy `skill/` removed.** After migration, the top-level `skill/` directory does not exist. No file in the new layout references `skill/scripts/...` or `skill/templates/...`.

### Non-Functional Requirements

**NFR1 — No lifecycle behavior change.** Every existing script's input contract and output behavior is preserved. A script that worked before the migration produces the same result after, modulo the new invocation name and the `$CLAUDE_PLUGIN_ROOT` resolution.

**NFR2 — Dogfooding preserved best-effort.** This repo's own `.specclaw/changes/` continues to work when the plugin is installed locally via `--plugin-dir .` and run against this repo as the host. If a conflict arises between dogfooding cleanliness and proper plugin design, the plugin wins.

**NFR3 — Skill descriptions are unambiguous and disjoint.** No two skills have descriptions that could plausibly route the same natural-language request. Reviewed together (see §FR3 and design.md).

**NFR4 — Bash 3.2 compatible.** Scripts must continue to work on macOS's default bash (no associative arrays, no `${var,,}` lowercasing).

## Acceptance Criteria

AC1 — `cat plugins/specclaw/.claude-plugin/plugin.json | jq -r .name` returns `specclaw` and `version` is a valid semver `0.1.0`.

AC2 — `cat .claude-plugin/marketplace.json | jq -r .name` returns `chan4lk`. `jq '.plugins | length'` returns `1`. `.plugins[0].name` is `specclaw`, `.plugins[0].source` is `./plugins/specclaw`.

AC3 — `ls plugins/specclaw/skills/` lists at least 15 directories, each containing a `SKILL.md` with valid frontmatter (`description:` present, `disable-model-invocation: true` present).

AC4 — `ls plugins/specclaw/bin/` lists executable scripts (one per migrated lifecycle script). `file plugins/specclaw/bin/specclaw-build` reports a script with `#!/usr/bin/env bash` shebang.

AC5 — `grep -rn "skill/scripts\|skill/templates" plugins/ .claude-plugin/ README.md CHANGELOG.md` returns zero matches (existing archived change docs under `.specclaw/changes/` may reference old paths and are allowed).

AC6 — `claude --plugin-dir plugins/specclaw` loads the plugin without error in a sibling test directory containing an empty `.specclaw/`.

AC7 — In that test directory, invoking `/specclaw:init` creates `.specclaw/config.yaml` in the test directory (not in the plugin install dir).

AC8 — In this repo (dogfood test): running `plugins/specclaw/bin/specclaw-validate-change .specclaw claude-plugin-packaging plan` (with the plugin loaded via `--plugin-dir plugins/specclaw`) prints `✅ Ready for plan`.

AC9 — README contains a `## Installation` section with the `/plugin marketplace add` and `/plugin install` commands.

AC10 — `CHANGELOG.md` contains an entry for `[0.1.0]` documenting the plugin packaging.

## Edge Cases

**EC1 — Plugin used in a repo with no `.specclaw/` yet.** Running `/specclaw:propose` before `/specclaw:init` must fail with a clear error pointing at `init`.

**EC2 — `$CLAUDE_PLUGIN_ROOT` unset.** Happens in `--plugin-dir` dev mode on older Claude Code versions. The `BASH_SOURCE`-derived fallback must work.

**EC3 — Host repo has its own `bin/` directory.** The plugin's `bin/` is prepended to `PATH` by Claude Code; the host's `bin/` is not shadowed since it's not on `PATH` by default.

**EC4 — Two specclaw versions enabled.** Plugin system handles this; not our concern, but document in README that only one version should be enabled at a time.

**EC5 — Slash command name conflicts.** `/specclaw:pr` and `/specclaw:pr-azdo` are distinct; descriptions must make the difference obvious.

**EC6 — Scripts that source other scripts.** If any current script does `source skill/scripts/foo.sh`, that line breaks once names change. Audit during build.

## Dependencies

- No external dependencies introduced. Continues to depend on: `bash`, `git`, `gh` CLI, optional `jq`.
- Claude Code v2.1+ (for `/plugin install` and `$CLAUDE_PLUGIN_ROOT`).

## Notes

- Marketplace name is `chan4lk` — separate from plugin name `specclaw`. Users install with `/plugin install specclaw@chan4lk`. Future plugins from the same owner go under `plugins/<name>/` in this repo and are installed as `<name>@chan4lk`.
- Archived change docs under `.specclaw/changes/` that reference `skill/scripts/...` are historical and stay as-is.
- The official Anthropic marketplace submission is a separate follow-up change.
- The repo URL slug remains `chan4lk/specclaw`. If a multi-plugin future warrants it, the repo can later be renamed (e.g. `chan4lk/plugins`) without breaking installs — users would only need to re-add the marketplace.
