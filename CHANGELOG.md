# Changelog

All notable changes to specclaw are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] — 2026-05-15

### Fixed
- `/specclaw:pr` and `/specclaw:pr-azdo` now auto-stage and commit the
  `.specclaw/changes/<change>/` directory (proposal, spec, design, tasks,
  status, verify-report, errors, learnings) before opening the PR.
  Previously these planning artifacts were never committed by
  `specclaw-build commit` (which only commits each task's declared files),
  so PRs landed without the spec/design/verify trail. Reviewers had to
  read the linked GitHub Issue to see the plan. Now the artifacts ship
  in the PR diff alongside the code. `.specclaw/.env` is already
  gitignored and is not touched.

## [0.3.1] — 2026-05-15

### Fixed
- `yaml_val` across all 9 scripts (`specclaw-build`, `specclaw-pr`,
  `specclaw-azdo-pr`, `specclaw-azdo-issue`, `specclaw-jira-issue`,
  `specclaw-gh-sync`, `specclaw-validate-change`, `specclaw-verify`,
  `specclaw-verify-context`) now strips inline `#` comments before
  stripping surrounding quotes. Previously, a config line like
  `branch_prefix: "specclaw/"   # Prefix for feature branches` would
  parse to `specclaw/"   # Prefix for feature branches` instead of
  `specclaw/`, causing `specclaw-build setup` to construct malformed
  branch names. Caught when another Claude session ran `specclaw build`
  against a freshly-init'd config.

## [0.3.0] — 2026-05-15

### Added
- **Azure Boards integration** for proposal tracking — symmetric to the existing
  GitHub Issues and Jira integrations. Opt-in via `azdo.boards.sync: true` in
  `config.yaml`.
- New `specclaw-azdo-issue` script with subcommands `create`, `update`,
  `comment`, `close`, `link-pr`. Targets the ADO REST Work Items API.
  Reuses credentials from `/specclaw:auth-azdo`.
- New `/specclaw:azdo-issue` skill (model-invokable).
- Lifecycle hooks: `/specclaw:propose` creates the Work Item, `/specclaw:plan`
  updates description with the task checklist, `/specclaw:build` comments on
  task failures and wave-ends, `/specclaw:verify` comments with the verdict,
  `/specclaw:archive` posts a closing comment and adds a
  `closed-by-specclaw` tag.
- `/specclaw:pr-azdo` now **auto-links** the created PR to the Work Item via
  the ADO REST relations API (`ArtifactLink` of type `Pull Request`) so the
  PR shows up under the Work Item's "Development" panel. Failure is
  non-fatal — the PR is independently created.
- New config keys under `azdo.boards`: `sync` (default `false`),
  `work_item_type` (default `Feature`), `tag` (default `specclaw`).

### Notes
- specclaw does **not** auto-transition Work Item state — humans drive ADO
  state. State machines differ across process templates (Agile / Scrum /
  Basic / custom), so any auto-transition logic would be wrong somewhere.
  specclaw writes description, comments, and tags only.
- Default behavior is unchanged. Users who don't set `azdo.boards.sync: true`
  see no difference from v0.2.5.

## [0.2.5] — 2026-05-15

### Fixed
- Cross-platform `sed -i` portability. GNU sed accepts `sed -i "expr" file`
  but BSD sed (macOS) treats the expression as the backup-extension argument
  and the file path as the script — leading to errors like
  `sed: 1: ".../config.yaml": command c expects \ followed by text`.
  Added a `sed_i` helper to all 6 scripts that use in-place edits
  (`specclaw-auth-azdo`, `specclaw-auth-jira`, `specclaw-pr`,
  `specclaw-azdo-pr`, `specclaw-update-task-status`, `specclaw-detect-patterns`)
  which uses `sed -i ''` on Darwin and `sed -i` elsewhere.
- `specclaw-update-task-status --help` no longer errors on BSD sed
  (`extra characters at the end of p command`). Added a missing
  semicolon to the brace-group sed script.

## [0.2.4] — 2026-05-15

### Fixed
- `specclaw-auth-azdo` / `specclaw-auth-jira` no-tty error now prints a
  copy-paste-ready command with the script's **absolute path** and the
  resolved absolute path to `.specclaw/`. Previously the message said
  `cd <your-project>; specclaw-auth-azdo .specclaw`, which didn't work
  because the plugin lives in Claude Code's cache (not on the user's PATH)
  and the angle brackets were getting HTML-escaped by Claude Code's UI.

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
