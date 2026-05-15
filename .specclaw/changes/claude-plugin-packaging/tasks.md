# Tasks: Package specclaw as an installable Claude Code plugin

**Change:** claude-plugin-packaging
**Created:** 2026-05-15
**Total Tasks:** 11

## Summary

Mechanical reorg of `skill/` into Claude Code plugin layout, plus two new manifests, a README install section, a CHANGELOG, and end-to-end install validation. No lifecycle behavior changes. Three waves: scaffolding → migration → validation.

## Tasks

### Wave 1 — Scaffolding (parallelizable)

- [x] `T1` — Write `plugins/specclaw/.claude-plugin/plugin.json` manifest
  - Files: `plugins/specclaw/.claude-plugin/plugin.json`
  - Estimate: small
  - Depends: —
  - Notes: name `specclaw`, version `0.1.0`, description, author, homepage `https://github.com/chan4lk/specclaw`, repository `chan4lk/specclaw`, license `MIT` (confirm from LICENSE)

- [x] `T2` — Write `.claude-plugin/marketplace.json` catalog
  - Files: `.claude-plugin/marketplace.json`
  - Estimate: small
  - Depends: —
  - Notes: marketplace name `chan4lk`, owner block (name from git config), `plugins[]` with one entry: `{ "name": "specclaw", "source": "./plugins/specclaw", "version": "0.1.0", "description": "..." }`. Schema designed so adding future plugins is purely an array push.

- [x] `T3` — Add `CHANGELOG.md` with `[0.1.0]` entry
  - Files: `CHANGELOG.md`
  - Estimate: small
  - Depends: —
  - Notes: Keep-a-Changelog format. Document plugin packaging, `chan4lk` marketplace, skill decomposition, `bin/` migration, removal of `skill/`.

### Wave 2 — Migration (sequential within tracks, tracks parallel)

- [x] `T4` — Move `skill/templates/` → `plugins/specclaw/templates/` and `skill/references/` → `plugins/specclaw/references/`
  - Files: `plugins/specclaw/templates/*`, `plugins/specclaw/references/*`, delete `skill/templates/`, delete `skill/references/`
  - Estimate: small
  - Depends: —
  - Notes: `git mv` to preserve history.

- [x] `T5` — Move and rename scripts: `skill/scripts/<name>.sh` → `plugins/specclaw/bin/specclaw-<name>`
  - Files: `plugins/specclaw/bin/specclaw-*` (18 scripts), delete `skill/scripts/`
  - Estimate: medium
  - Depends: —
  - Notes: `git mv` each. Strip `.sh` extension. Prefix `specclaw-`. `chmod +x`. Audit `#!/usr/bin/env bash` shebang on every one.

- [x] `T6` — Patch scripts to use `$CLAUDE_PLUGIN_ROOT` and rewrite internal invocations
  - Files: every file in `plugins/specclaw/bin/`
  - Estimate: medium
  - Depends: T5
  - Notes: Add `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"` near the top. Replace any `skill/templates/` with `$PLUGIN_ROOT/templates/`, `skill/references/` with `$PLUGIN_ROOT/references/`. Replace any cross-script `bash skill/scripts/X.sh` with the on-PATH form `specclaw-X`. Audit `source` lines.

- [x] `T7` — Decompose `skill/SKILL.md` into 15 `plugins/specclaw/skills/<verb>/SKILL.md` files
  - Files: `plugins/specclaw/skills/{init,propose,plan,build,learn,patterns,verify,pr,pr-azdo,auth-azdo,auth-jira,issue,status,archive,auto}/SKILL.md`
  - Estimate: large
  - Depends: T6 (so script names referenced inside SKILL.md bodies are correct)
  - Notes: For each verb, extract its `### `specclaw foo`` section from old SKILL.md, drop the heading, prepend YAML frontmatter:
    ```
    ---
    description: <from design.md KD6 table>
    disable-model-invocation: true
    ---
    ```
    Rewrite every `bash skill/scripts/X.sh` to the on-PATH invocation. Verify each description is disjoint from the others (re-read all 15 side by side once written).

- [x] `T8` — Delete `skill/` directory
  - Files: delete `skill/`
  - Estimate: small
  - Depends: T4, T5, T7
  - Notes: `git rm -r skill`. Final check: `grep -rn 'skill/' plugins/ README.md CHANGELOG.md` returns empty.

### Wave 3 — Documentation & Validation

- [x] `T9` — Update README with install instructions
  - Files: `README.md`
  - Estimate: small
  - Depends: T1, T2
  - Notes: Add `## Installation` section with `/plugin marketplace add chan4lk/specclaw` and `/plugin install specclaw@chan4lk`. Add minimum Claude Code version note. Quickstart: `/specclaw:init` then `/specclaw:propose "..."`. Mention future plugins from `chan4lk` will be installable from the same marketplace.

- [x] `T10` — End-to-end install smoke test
  - Files: (no repo changes; produces `verify-report.md` notes)
  - Estimate: medium
  - Depends: T8, T9
  - Notes: In a sibling temp directory: `claude --plugin-dir <path-to-specclaw-repo>/plugins/specclaw`. Inside, run `/specclaw:init`, confirm `.specclaw/config.yaml` is created in the temp dir (not in plugin repo). Run `specclaw-validate-change .specclaw <a-known-change> plan` against this repo (dogfood). Document results.

- [x] `T11` — Dogfood validation in this repo
  - Files: (no changes; verification only)
  - Estimate: small
  - Depends: T8
  - Notes: From this repo, after migration, `specclaw-validate-change .specclaw claude-plugin-packaging build` should pass. Confirm `.specclaw/changes/` is readable and writeable. AC8 from spec.md.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
