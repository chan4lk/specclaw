# Proposal: Lean, output-first greenfield flow

**Created:** 2026-10-11
**Status:** 🟡 Draft

## Problem

Greenfield SpecClaw is slow and produces no output a person can check:

- **Changes are split by layer, not by screen.** In a production project using SpecClaw, one screen-bearing feature shipped as four backend parts (building blocks, page builders, endpoints) before the part that added the screen. That was four merges in which nobody could see anything.
- **Most of the output is paperwork.** In one day of that project, 44% of added lines were docs and `.specclaw` records, 33% were tests, and only 19% were product source. Each change carries 6–11k words of artifacts, and a single spec.md can reach 4,000 words. One PR went through 4 review rounds.
- **The instructions cost tokens before any work starts.** The six lifecycle skills come to about 13.5k words, 5.3k of them in `propose` alone, and most of that is brownfield gating that never applies to greenfield. Every installed skill's description loads every session, including 14 `bf-*` skills and 14 `bf-*` agents (about 76k words in total) that a greenfield user never invokes.
- **No coding standard is enforced.** Each project rewrites its own CLAUDE.md, and nothing mechanical catches duplicated code, oversized files or complex functions in greenfield work.

## Proposed Solution

A **lean, output-first greenfield flow**, delivered in four stages. Each stage ships and can be used on its own.

### Stage 1: Lean flow, mock first

- **Switch.** `config.yaml` gets `flow: lean | full`. `specclaw:init` writes `lean` for new projects. A config without the key reads as `full`, so existing projects behave exactly as they do today.
- **Mock first.** A single plain-HTML project mock lives at `.specclaw/mock/index.html`. It has no external dependencies and fake data only, and opens in any browser, so it works the same under Claude Code, Codex and dsh.
  - **Change 001** of a lean project is always the minimal mock: the overall layout of the app. Its only acceptance criterion is that the user opens it and recognises the app.
  - **Every later proposal** edits the mock to show what it adds, with the change ID marked on the affected screens. The user approves the mock delta together with the text. Nothing is built until then.
- **One file per change.** `.specclaw/changes/NNN-slug/change.md` holds:
  - Problem (2–3 lines)
  - Mock delta (what changed on screen, plus an anchor into the mock)
  - Numbered acceptance criteria
  - Tasks (added by `plan`)
  - Verify (one line per criterion, plus screenshot paths)

  A lean change has no proposal.md, spec.md, design.md, tasks.md, status.md, learnings.md, follow-ups.md or verify-report.md. Phase state stays in `state.json`.
- **Phases:**

  | Phase | Lean behaviour |
  |---|---|
  | `plan` | Adds tasks to `change.md`, ordered UI first, then backend, then integration. No waves and no design doc. |
  | `build` | One pass and one commit per task. At most one test per acceptance criterion. At most 2 loop iterations. |
  | `verify` | Runs the configured test, lint and build commands, records one line per criterion, and screenshots the real screen next to the mock section. |
  | `pr` | PR body = `change.md` + the screenshots. |
- **Lean defaults:** `party.enabled: false`, `workflow.code_review: false`, `loop.max_iterations: 2`. There are no review rounds: any review finding is fixed in one pass or recorded as dropped.
- **Dispatcher skills.** Each lifecycle `SKILL.md` becomes about 300 words or fewer of lean instructions, plus one line: when `flow: full`, read `references/full/<phase>.md` and follow it instead. Today's text moves into those reference files unchanged.

### Stage 2: Split into plugins, trim everything

- **Four plugins**, all in the same repo and the one `chan4lk` marketplace (both `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`):
  - `specclaw` (core): init, propose, plan, build, verify, pr, status, archive.
  - `specclaw-bf`: the 14 `bf-*` skills, 14 `bf-*` agents, the `specclaw-bf-*` scripts, the brownfield templates and tests. It also provides `specclaw-bf:propose`, which runs the foundation, prototype, backlog, stub and split gates (moved out of core `propose`) and then hands over to `specclaw:propose`.
  - `specclaw-sync`: pr-azdo, auth-azdo, azdo-issue, auth-jira, issue, and the gh, azdo and jira sync scripts. Core lifecycle steps call a sync script only if it is installed (`command -v`); otherwise they skip silently.
  - `specclaw-extras`: automation (auto, loop as its own command, the party panel and its agents) and knowledge (learn, patterns, context, author-spec, debug, renumber).
- **Trim.** Every skill and agent description becomes one sentence covering what it does and when to use it, within `tests/description-lint-baseline.txt`'s rules. The README is cut to install, quickstart (lean flow) and a plugin table, with long material moved to `docs/`. The session-start hook's injected text stays within its existing cap.

### Stage 3: Coding presets

- **One rules file per technology,** `presets/<name>.md` in core, about 40 lines each. The project chooses with `presets: [nextjs, dotnet]` in `config.yaml`. `init` detects the stack from `package.json`, `*.csproj` or `pyproject.toml`, then confirms with the user. `build` reads only the listed presets.
- **`base` always applies:**
  - No comments in code files (tool pragmas allowed).
  - 80 lines at most per file, tests included.
  - One test per acceptance criterion.
  - No abstraction without at least two callers, unless a preset requires the boundary.
- **Per-technology presets:**

  | Preset | Main rules |
  |---|---|
  | `dotnet` | Clean Architecture: Domain → Application → Infrastructure → Api, inward-only references. Minimal APIs. xUnit. Nullable enabled. |
  | `nextjs` | App Router. Server components by default. An auth guard in `middleware.ts` on every protected route. Zod at server actions and route handlers. Strict TypeScript. Vitest + Playwright. |
  | `react-spa` | Vite, React Router, TanStack Query, a route-level auth guard component, Zod on API responses. |
  | `node` | Strict TypeScript, ES modules, Zod at boundaries, Vitest. |
  | `python` | 3.12, uv, ruff + mypy, Pydantic at boundaries, pytest, FastAPI for APIs. |
- **Overrides** go in config, e.g. `preset_overrides: { max_lines: 120 }`. They are recorded and never applied silently.
- **`specclaw-preset-check`** checks the mechanical rules: line counts, comment lines and the .NET project-reference direction. It is a `verify` gate.

### Stage 4: Quality scan and refactor pass

- **`specclaw-quality-scan`** in core, extracted from `specclaw-bf-quality-collect`'s jscpd and lizard code; `specclaw-bf` then uses it from core. It runs `npx jscpd` and `uvx lizard` and prints a compact JSON list of only the hotspots: each duplicate block with both locations, and each function over the complexity or length threshold. The agent reads that list, never the codebase.
- **Refactor step at the end of every lean `build`:**
  1. Scan.
  2. Extract each duplicate into the preset's shared library (`*.Common`, `src/lib` or `packages/shared`, or a `common` package), using base classes, generic handlers or shared hooks.
  3. Re-scan and run the tests. Keep the refactor only if duplication dropped and the tests pass; otherwise revert it.
- **Verify gate:** verify fails above the existing `quality.*_high` thresholds. `change.md` records the before and after numbers.

## Scope

### In Scope
- `flow:` switch, lean `change.md` template, mock skeleton template, lean init/propose/plan/build/verify/pr/status/archive.
- Dispatcher `SKILL.md` files, with full-flow text moved verbatim to `references/full/`.
- Plugin split into specclaw, specclaw-bf, specclaw-sync and specclaw-extras; both marketplace manifests; Codex packaging for each.
- Trimmed descriptions, README and docs index.
- Presets: base, python, nextjs, node, dotnet, react-spa; `specclaw-preset-check`.
- `specclaw-quality-scan` and the build refactor step; verify gates for preset and quality.

### Out of Scope
- Any change to how the full flow behaves. It moves, but its text is unchanged.
- Any change to brownfield behaviour beyond relocating it to `specclaw-bf`.
- Migrating existing projects to lean. They opt in by setting `flow: lean`.
- Presets for Go, Java and other stacks (later).
- Any application built with the lean flow. The first pilot project starts after stage 1 ships.

## Impact

- **Size:** architectural. It adds a new flow and new plugin boundaries that other plugins and existing projects depend on.
- **Files affected:** about 200, most of them moves (bf, sync and extras files) rather than new code.
- **Complexity:** large, delivered in four separately shippable stages.
- **Risk:** medium. Mitigations:
  - `flow` defaults to `full` when the key is absent.
  - Full-flow text moves verbatim.
  - Every existing `tests/run-*.sh` must pass from its new plugin location before stage 2 merges.

## Decisions

- **Screenshots** (decided 2026-10-11): verify uses Playwright (`npx playwright screenshot`) when it is available. Otherwise it prints the URL and the mock anchor, and the person compares by eye. A failed screenshot never counts as a pass.
- **Versioning** (decided 2026-10-11): all four plugins share one version and bump together, in both marketplace manifests and every `plugin.json`.
- **Missing-plugin notice** (decided 2026-10-11): the session-start hook prints one line when the config uses a feature whose plugin isn't installed (bf, azdo/jira sync, party/auto), naming the install command.
- **Tracker issues for lean changes** (accepted with approval, 2026-10-11): when `specclaw-sync` is installed and `github.sync: true`, a lean change still creates its issue at propose time, as today.

## Open Questions

None open.


---

**To proceed:** Review this proposal and approve to begin planning.
