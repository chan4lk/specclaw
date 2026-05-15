# Changelog

All notable changes to specclaw are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] — 2026-05-15

### Fixed
- `specclaw-auth-azdo` and `specclaw-auth-jira` no longer crash with
  `/dev/tty: Device not configured` when an agent (like Claude Code)
  invokes them. They now detect missing `/dev/tty` upfront and exit with
  clear instructions telling the user to run the command directly from
  their own terminal (so they can paste their PAT / API token securely
  without going through an agent).
- The `auth-azdo` and `auth-jira` skill bodies now explicitly tell Claude
  to delegate the run to the user rather than invoking it.

## [0.2.2] — 2026-05-15

### Changed
- Tightened `/specclaw:propose` skill description to `INVOKE IMMEDIATELY` —
  Claude now fires the skill on the first turn when the user mentions a
  proposal/feature idea/change request, instead of gathering details
  conversationally first. The skill itself asks once for missing details.

## [0.2.1] — 2026-05-15

### Added
- `specclaw-ensure-init` helper script that idempotently creates `.specclaw/`
  if missing, using the current directory's basename as the project name.
- Every non-init skill now runs `specclaw-ensure-init` as Step 0, so any
  specclaw command (e.g. `/specclaw:propose`) works in a fresh project
  without requiring `/specclaw:init` first.

## [0.2.0] — 2026-05-15

### Changed
- Enabled model-invocation on 13 of 15 skills (everything except `auth-azdo`
  and `auth-jira`). Claude now routes conversationally — saying "i have a
  proposal" auto-fires `/specclaw:propose`. The two auth skills remain
  explicit-only because they handle credentials.

## [0.1.0] — 2026-05-15

First release as a Claude Code plugin.

### Added
- **Marketplace `chan4lk`** at `.claude-plugin/marketplace.json` — repo doubles as
  the chan4lk plugin marketplace. Future plugins by the same owner will be added
  under `plugins/<name>/` and registered in the same marketplace.
- **Plugin manifest** at `plugins/specclaw/.claude-plugin/plugin.json` — name
  `specclaw`, version `0.1.0`, MIT licensed.
- **Per-verb skills** under `plugins/specclaw/skills/<verb>/SKILL.md` — one skill
  per lifecycle verb (`init`, `propose`, `plan`, `build`, `learn`, `patterns`,
  `verify`, `pr`, `pr-azdo`, `auth-azdo`, `auth-jira`, `issue`, `status`,
  `archive`, `auto`). All skills use `disable-model-invocation: true` so they only
  fire on explicit slash-command invocation.
- **Executables in `bin/`** — every lifecycle script lives at
  `plugins/specclaw/bin/specclaw-<name>` and is on `$PATH` while the plugin is
  enabled. No more `bash skill/scripts/...` invocations.

### Changed
- All scripts resolve plugin-internal resources via `$CLAUDE_PLUGIN_ROOT` with a
  `BASH_SOURCE`-derived fallback for `--plugin-dir` dev mode. Scripts operate on
  the host repo's current working directory for `.specclaw/` state.

### Removed
- Top-level `skill/` directory. The previous layout
  (`skill/SKILL.md` + `skill/scripts/*.sh` + `skill/templates/`) is gone.

### Installation
```
/plugin marketplace add chan4lk/specclaw
/plugin install specclaw@chan4lk
```

Requires Claude Code v2.1 or later.
