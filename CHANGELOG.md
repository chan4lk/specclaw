# Changelog

All notable changes to specclaw are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] — 2026-07-16

### Added
- **Smart base branch detection.** New `detect_base_branch()` (duplicated
  into `specclaw-build` and `specclaw-pr` per the self-contained-script
  convention) resolves the base as: `git.base_branch` config override →
  `origin/HEAD` (self-healing via `git remote set-head origin --auto`) →
  `gh repo view` default branch → `main`/`master` fallback. New config key
  `git.base_branch` (empty = auto).

### Fixed
- **`specclaw-build setup` no longer branches from arbitrary HEAD.** New
  change branches start from `origin/<base>` (fetched first, offline-safe
  local fallback); creating a branch while off-base prints a divergence
  warning so stacking is deliberate. Resume behavior unchanged. Setup JSON
  gains a `base_branch` field.
- **`specclaw-build finalize` merges into the detected base** instead of
  guessing `main`-else-`master`.
- **`specclaw-pr` no longer hardcodes `--base main`** — the PR targets the
  detected base; the version-bump comparison now uses the same single
  source of truth.

## [0.4.2] — 2026-05-24

### Fixed
- **`specclaw-detect-patterns` path doubling.** Script formed `patterns.md`
  and `changes/` paths as `$specclaw_dir/.specclaw/...` while every sibling
  bin script (and `/specclaw:build`) treats `$specclaw_dir` as already being
  `.specclaw`. Result: `scan` looked for `.specclaw/.specclaw/changes/<name>`
  (not found) and `ensure_patterns_file` created a stray
  `.specclaw/.specclaw/patterns.md` stub on every build. Fixed the four
  affected lines to use `$specclaw_dir/...` directly.

## [0.4.1] — 2026-05-21

### Added
- **Per-repo knowledge base.** Promoting a learning or pattern now
  writes to `.specclaw/knowledge/` in the target repo — never to the
  plugin. `spec_gap`/`design_gap` learnings go to `spec-guidelines.md`;
  `pattern`/`best_practice`/`agent_issue` learnings and pattern
  prevention rules go to `agent-hints.md`. Plugin stays versioned and
  generic; repos accumulate their own knowledge over time.
- **Build agent auto-receives repo knowledge.** `specclaw-build-context`
  injects `.specclaw/knowledge/agent-hints.md` into every coding-agent
  prompt as a "Repo Knowledge Base" section when the file exists.
- **Knowledge templates.** `templates/knowledge/agent-hints.md` and
  `templates/knowledge/spec-guidelines.md` seed new knowledge bases.

## [0.4.0] — 2026-05-20

### Added
- **Agent guardrails injected into every coding agent.** Vendored
  Andrej Karpathy's CLAUDE.md (four behavioral rules: Think Before
  Coding, Simplicity First, Surgical Changes, Goal-Driven Execution)
  as `plugins/specclaw/references/agent-guardrails.md` (MIT, upstream
  `2c60614`). `specclaw-build-context` now prepends the guardrails as
  the first section of every coding-agent prompt — always-on, no
  config flag. Goal: reduce diff bloat, scope deviations, and
  speculative abstractions in agent-produced code.
- **Skill docs cross-reference the guardrails.** `skills/build`
  surfaces the auto-injection under Key Principles; `skills/plan`
  applies rules 1 & 2 to task decomposition; `skills/verify` frames
  itself as rule 4's goal-check loop against `spec.md` ACs.

### Behavior
- Missing `references/agent-guardrails.md` at build time emits a
  stderr warning and continues — packaging bug, not a build-blocker.

## [0.3.3] — 2026-05-15

### Fixed
- **Critical:** `sed_i` helper in 5 scripts (`specclaw-auth-azdo`,
  `specclaw-auth-jira`, `specclaw-pr`, `specclaw-azdo-pr`,
  `specclaw-detect-patterns`) had a recursive bug on **Linux only** —
  the Linux branch called `sed_i` instead of `sed -i`, producing
  infinite recursion → stack overflow → segmentation fault. Symptom:
  `specclaw-auth-azdo` segfaulted on Linux immediately after the
  `✅ Token valid` line, before saving credentials. macOS users were
  unaffected because the Darwin branch was correct. Root cause:
  v0.2.5's Python patcher's `re.sub(r'\bsed -i "', 'sed_i "', txt)`
  also matched inside the helper body and replaced its own fallback
  call. Fixed by reverting the Linux branch to `sed -i "$expr" "$@"`.

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
