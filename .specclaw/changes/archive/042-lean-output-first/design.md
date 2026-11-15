# Design: Lean, output-first greenfield flow

**Change:** 042-lean-output-first

## Approach

The lean flow runs **beside** the full flow, behind one switch. The plugin split is mostly file moves (`git mv`), so history follows the files. All new mechanics are small scripts. Skills stay as instructions that call those scripts, the same pattern the repo already uses ("skills call these helpers rather than reimplementing mechanics", `.specclaw/context.md`).

## Repository layout after the change

```
plugins/
  specclaw/          core: init propose plan build verify pr status archive
    skills/<phase>/SKILL.md       lean text + dispatch line
    references/full/<phase>.md    0.7.9 text, brownfield sections removed
    templates/lean/{change.md,mock.html}
    presets/{base,python,nextjs,node,dotnet,react-spa}.md
    bin/  core scripts + specclaw-flow, -screenshot, -preset-check, -quality-scan
  specclaw-bf/       bf-* skills/agents/bins/templates/refs/tests + skills/propose (gates → specclaw:propose)
  specclaw-sync/     gh/azdo/jira skills + bins + their tests
  specclaw-extras/   auto loop learn patterns context author-spec debug renumber + party/spec-author agents + specclaw-party
```

Each plugin has `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`, and is listed in both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`.

## Key decisions

1. **Dispatch line, not two skill sets.** Each core `SKILL.md` opens with:

   > Run `specclaw-flow .specclaw`. If it prints `full`, read `$CLAUDE_PLUGIN_ROOT/references/full/<phase>.md` and follow it instead of this file.

   A lean run never reads the full text. A full-flow project pays one extra file read. Keeping one skill name per verb keeps triggers and descriptions single.
2. **The `flow` default is `full` when absent.** Every existing config upgrades without change. Only `init` writes `lean`.
3. **A lean change reuses phase state.** `state.json` and `specclaw-set-phase` stay unchanged. `validate-change` learns one rule: when `change.md` exists, it is the artifact for proposal, spec, design and tasks. `parse-tasks` gets a section extractor so it reads `## Tasks` from `change.md` with the same line grammar.
4. **The mock is one self-contained HTML file:** inline CSS, a nav built from `<section data-change>` ids, and fake data inline. No CDN, so it renders offline under any harness. Change ownership is the `data-change` attribute.
5. **Screenshots** go through `specclaw-screenshot <target> <out.png>`, which wraps `npx --no-install playwright screenshot`:
   - exit 0: PNG written
   - exit 3: Playwright unavailable
   - any other code: a real failure
6. **Cross-plugin calls use the bare name behind `command -v`.** There is no shared library across plugins. The existing `bin/` scripts are self-contained (only the two bf scripts use `source`, and both move together).
7. **The brownfield gates move out of core `propose`.** Steps 1, 1a and 2a–2d of 0.7.9 `propose` go to `specclaw-bf/skills/propose/SKILL.md`, which ends with "now follow `specclaw:propose`". The gates were already inert without `rebuild-backlog.md`, so removing them from core changes nothing for greenfield.
8. **One version.** `plugin.version_files` lists all 8 `plugin.json` files and both marketplace files, so `specclaw-pr`'s existing `ensure_version_bumped()` bumps them together.
9. **Presets are rule text plus one checker.** `specclaw-preset-check` is Python 3 (allowed in `bin/`):
   - line count per file
   - comment detection by extension (`#` for py; `//` and `/* */` for ts/tsx/js/cs), with a pragma allow-list (`eslint-disable`, `@ts-`, `type: ignore`, `noqa`, `#pragma`, `#nullable`, shebang)
   - a `.csproj` `ProjectReference` direction check using layer order Domain < Application < Infrastructure < Api, read from project names

   It scans git-tracked files only and applies the same exclusions as `lib/quality-exclusions.yaml`.
10. **The quality scan is extracted, not rewritten.** The jscpd and lizard invocation and parsing in `specclaw-bf-quality-collect` move into `specclaw-quality-scan`, which owns `quality.*` thresholds and exclusions. `bf-quality-collect` calls it and keeps its brownfield-only rendering.
11. **The refactor step is skill text, guarded by measurement.** The agent reads only the scan JSON. It keeps a refactor only if the re-scan shows lower `totals.duplicated_lines` and the test command passes; otherwise it runs `git checkout -- .` on that refactor.

## File changes map

| Area | Files |
|---|---|
| New scripts | `bin/specclaw-flow`, `bin/specclaw-screenshot`, `bin/specclaw-preset-check`, `bin/specclaw-quality-scan` |
| Changed scripts | `specclaw-init`, `specclaw-validate-change`, `specclaw-parse-tasks`, `specclaw-update-status`, `specclaw-reconcile`, `hooks/session-start`, `specclaw-bf-quality-collect` |
| Templates | `templates/config.yaml` (`flow`, `presets`, `preset_overrides`), `templates/lean/change.md`, `templates/lean/mock.html` |
| Skills | 8 core `SKILL.md` rewritten; `references/full/*.md` added; bf/sync/extras skills moved |
| Packaging | 3 new plugin dirs, 6 new manifests, 2 marketplace files, `.agents/skills/specclaw/SKILL.md` routing |
| CI and tests | `.github/workflows/ci.yml` paths; new `run-lean-flow-tests.sh`, `run-preset-check-tests.sh`, `run-quality-scan-tests.sh`, `run-plugin-split-tests.sh`; `run-codex-plugin-tests.sh` extended to 4 plugins |
| Docs | `README.md`, `docs/index.md`, `CHANGELOG.md`, `.specclaw/context.md` |

## Risks

| Risk | Mitigation |
|---|---|
| A moved test suite still points at core paths | AC-14: every suite runs in CI from its new path before merge. |
| The Codex adapter routes to a moved skill | `run-codex-skill-tests.sh` is updated in the same task as the move. |
| An agent ignores the dispatch line and runs lean steps on a full project | The dispatch line is the first instruction. `validate-change` refuses a lean artifact set on a `full` project and the reverse. |
| Comment detection false positives (a `#` inside strings) | Only whole-line comments are flagged. Trailing comments are left alone. |

## Grounding sources

- `.specclaw/context.md`:
  - "skills call these helpers rather than reimplementing mechanics"
  - "Every test suite must be registered in `.github/workflows/ci.yml`"
  - "`tests/shellcheck-gate.sh` passes with `shellcheck-baseline.txt` unchanged"
- `plugins/specclaw/tests/run-description-lint-tests.sh`: "LEN ≤ 300 characters. TRIGGER says WHEN to use the skill… NARRATION carries no workflow narration"
- `plugins/specclaw/templates/config.yaml` `quality:` block: the existing `*_warn` / `*_high` thresholds are reused unchanged.
