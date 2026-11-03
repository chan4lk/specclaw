# Spec: Lean, output-first greenfield flow

**Change:** 042-lean-output-first
**Size:** architectural
**Source:** proposal.md (approved 2026-10-11)

## Assumptions

- Plugin `bin/` directories are on `PATH` for the agent's shell in Claude Code and Codex, so one plugin calls another plugin's script by its bare name (every skill already does this today).
- "Full-flow text moves verbatim" means verbatim **minus the brownfield sections**, which move to `specclaw-bf` (proposal Stage 2).
- The four stages are ordered waves. Stage 1 is usable as soon as its waves land.

## Functional Requirements

### Stage 1: Lean flow
- **FR-1** `config.yaml` has a top-level `flow:` key. `specclaw-flow .specclaw` prints `lean` or `full`, and prints `full` when the key or the config is absent.
- **FR-2** `specclaw-init` writes `flow: lean`, `party.enabled: false`, `workflow.code_review: false` and `loop.max_iterations: 2` for new projects, and creates `.specclaw/mock/index.html` from the mock template.
- **FR-3** A lean change is `.specclaw/changes/NNN-slug/change.md` with these sections: `## Problem`, `## Mock Delta`, `## Acceptance Criteria`, `## Tasks`, `## Verify`. Phase state stays in `state.json` via `specclaw-set-phase`.
- **FR-4** `specclaw-validate-change`, `specclaw-update-status`, `specclaw-reconcile` and `specclaw-parse-tasks` accept a lean change (`change.md` instead of proposal/spec/design/tasks). Tasks in `change.md` use the existing task-line format.
- **FR-5** Lean `propose`:
  - For change 001 when the mock is still the template, it writes the minimal mock.
  - Otherwise it edits the mock: adds or changes a `<section data-change="NNN-slug">` and fills `## Mock Delta` with an anchor link.
  - It stops for approval.
- **FR-6** Lean `plan` appends `## Tasks`, ordered UI first, then backend, then integration. It writes no other file.
- **FR-7** Lean `build`: one commit per task, at most one test per acceptance criterion, loop capped at `loop.max_iterations`, no task-review or party spawns.
- **FR-8** Lean `verify`:
  - Runs the configured test, lint and build commands.
  - Writes one line per acceptance criterion under `## Verify`.
  - Runs `specclaw-screenshot` for the real screen and the mock anchor.
  - Exit 3 from the screenshot means Playwright is unavailable: verify prints both locations and asks the human to compare. A missing screenshot is never recorded as a pass.
- **FR-9** Lean `pr`: the PR body is `change.md` plus the screenshot paths.
- **FR-10** Each core lifecycle `SKILL.md` (init, propose, plan, build, verify, pr, status, archive) has lean instructions plus a dispatch line to `references/full/<phase>.md` when `flow` is `full`.

### Stage 2: Plugin split
- **FR-11** The repo ships `plugins/specclaw`, `plugins/specclaw-bf`, `plugins/specclaw-sync` and `plugins/specclaw-extras`. Each has a Claude and a Codex manifest. Both marketplace files list all four.
- **FR-12** `specclaw-bf` holds every `bf-*` skill, agent and script, the brownfield templates, references and tests, and a `propose` skill that runs the brownfield gates and then hands over to `specclaw:propose`. No core skill or reference mentions `bf`, `rebuild` or `brownfield`.
- **FR-13** `specclaw-sync` holds the pr-azdo, auth-azdo, azdo-issue, auth-jira and issue skills, plus `specclaw-gh-sync`, `specclaw-azdo-*`, `specclaw-jira-issue` and `specclaw-auth-*`. Core calls them only behind `command -v`.
- **FR-14** `specclaw-extras` holds the auto, loop, learn, patterns, context, author-spec, debug and renumber skills, plus the party and spec-author agents and `specclaw-party`. The `specclaw-loop` script stays in core.
- **FR-15** All four plugins share one version, kept equal in every `plugin.json` and both marketplace files.
- **FR-16** The session-start hook prints one line per feature the project's config uses whose plugin is missing, naming the install command:
  - bf: `.specclaw/analysis/` exists
  - sync: `github.sync`, `azdo.enabled` or `jira.enabled` is true
  - extras: `party.enabled` is true or `automation` is configured
- **FR-17** Every skill and agent description is one sentence and passes the description lint with no new baseline entries. The root README covers install, the lean quickstart and the plugin table.

### Stage 3: Presets
- **FR-18** `plugins/specclaw/presets/` holds `base.md`, `python.md`, `nextjs.md`, `node.md`, `dotnet.md` and `react-spa.md`, each 60 lines or fewer, with the rules listed in the proposal.
- **FR-19** `config.yaml` has `presets: [..]` and `preset_overrides: {..}`. `init` detects candidates from manifests and asks the user to confirm. Lean `build` reads `base` plus the listed presets only.
- **FR-20** `specclaw-preset-check <root>` reports these violations as JSON and exits 1 if any exist:
  - files over `max_lines`
  - comment lines, with pragmas allowed
  - for `dotnet`, a `ProjectReference` from an inner layer to an outer one
- **FR-21** Lean `verify` fails when `specclaw-preset-check` exits 1.

### Stage 4: Quality scan
- **FR-22** `specclaw-quality-scan <root>` runs jscpd and lizard (via `npx` and `uvx`), applies `quality.exclusions`, and prints JSON with `duplicates[]` (each with both locations and line counts), `functions[]` (over the warn thresholds) and `totals`. With `--gate`, it exits 1 above any `_high` threshold. `specclaw-bf-quality-collect` uses it instead of its own copy.
- **FR-23** Lean `build` ends with a refactor step: scan, extract duplicates into the preset's shared location, re-scan, run the tests, and keep the refactor only if duplication dropped and the tests pass (otherwise revert it). The before and after totals go into `## Verify`.
- **FR-24** Lean `verify` runs `specclaw-quality-scan --gate`.

## Non-Functional Requirements

- **NFR-1** Each core lifecycle `SKILL.md` is 300 words or fewer of lean instructions, plus the dispatch line.
- **NFR-2** A project with no `flow` key behaves exactly as on 0.7.9. Every existing test suite passes from its new location.
- **NFR-3** Scripts follow `.specclaw/context.md`: Bash + coreutils, with `jq` and `python3` allowed in `bin/`; every suite registered in `ci.yml`; the shellcheck gate passes with the baseline unchanged.
- **NFR-4** New test suites carry one case per acceptance criterion and no more.

## Acceptance Criteria

1. **AC-1** `specclaw-flow` prints `full` for a config with no `flow` key and `lean` for `flow: lean`. (FR-1)
2. **AC-2** After `specclaw-init` in an empty directory: `flow: lean` and the three lean defaults are set, and `.specclaw/mock/index.html` exists and opens without network access (no external URLs). (FR-2)
3. **AC-3** A fixture lean change containing only `change.md` passes `specclaw-validate-change … build`, and `specclaw-parse-tasks` lists its tasks. (FR-3, FR-4)
4. **AC-4** `specclaw-screenshot` writes a PNG when Playwright is present and exits 3 otherwise. (FR-8)
5. **AC-5** Each of the 8 core lifecycle `SKILL.md` files has 300 words or fewer above its dispatch line, and its `references/full/<phase>.md` exists. (FR-10, NFR-1)
6. **AC-6** `grep -riE 'bf-|brownfield|rebuild' plugins/specclaw/skills plugins/specclaw/references` returns nothing. (FR-12)
7. **AC-7** All four plugins validate in the Codex plugin test, and the versions in all six manifest entries are equal. (FR-11, FR-15)
8. **AC-8** With `github.sync: true` and `specclaw-sync` not on `PATH`, the session-start hook prints the install line, and a lean propose does not fail. (FR-13, FR-16)
9. **AC-9** The description lint passes with a baseline the same size or smaller. (FR-17)
10. **AC-10** The 6 preset files exist, each 60 lines or fewer, and `init` in a dir with `package.json` containing `next` proposes `nextjs`. (FR-18, FR-19)
11. **AC-11** `specclaw-preset-check` exits 1 on these fixtures and 0 on a clean one:
    - an 81-line file
    - a comment line
    - a Domain→Infrastructure `ProjectReference`

    (FR-20)
12. **AC-12** `specclaw-quality-scan` on a fixture with a planted 20-line duplicate lists it with both locations, and `--gate` exits 1 when it is above the high threshold. (FR-22)
13. **AC-13** `run-quality-tests.sh` (the brownfield quality suite) passes using the shared scan. (FR-22, NFR-2)
14. **AC-14** All existing suites pass in CI from their new plugin locations. (NFR-2, NFR-3)

## Edge Cases

- **A `full` project that has `specclaw-extras` installed** keeps its party and auto behaviour. One without it: `propose` skips the panel silently, because the party step is already guarded by `party.enabled`.
- **The mock edited by two in-flight changes:** each change owns only its own `data-change` sections, and propose refuses to edit another change's section.
- **`npx` or `uvx` absent:** `quality-scan` prints `not_run` for that tool and never reports zero duplicates. `--gate` exits 2, and lean verify treats a not-run scan as a failure.
- **A non-UI project (library or CLI)** under lean: the mock is a sample-output page, so the same file shows example input and output.
