---
description: Automatically detects the target application's platform (Web/Desktop/Mobile/Hybrid/Embedded) and stack, dynamically selects the most effective E2E testing framework for it with a stated justification, and generates a Page Object Model plus a runnable E2E test script that asserts the application's own observable business behaviour — derived independently from the application's real features/flows and any flow description you give it. No fixed platform/language/framework list, and no dependency on /specclaw:bf-baseline or any captured Golden Master fixture — works standalone on whatever the target codebase actually is. Read-only with respect to application source — writes generated test/page-object files plus a persisted .specclaw/e2e/e2e-report.md, and — unless told not to — also runs the generated suite once via specclaw-bf-e2e-run — starting any backend/frontend/dependency service it needs that isn't already running, in order, and leaving already-running ones alone — to record real Pass/Fail/Skipped counts, Pass Percentage and Execution Time in that report, plus on-failure screenshots/video collected into .specclaw/e2e/artifacts/ and listed there. Also renders a standalone .specclaw/e2e/e2e-report.html (Bootstrap via CDN) mechanically from the finished markdown report — a plain-language verdict banner, a pass-rate donut chart, stat cards, and a Test Scenarios list grouped by module/feature (never by raw file path) — one card per scenario, with the individual checks it makes nested underneath (so it's plain why an aggregate "32 passed" sits above fewer named scenarios) and the file path itself demoted to a small de-emphasized metadata line — plus inline screenshot/video evidence up front for any non-technical reader, with the developer-oriented detail (stack, run commands) tucked behind one collapsible "Technical Details" section — for stakeholders who'd rather open a styled page than read markdown. A one-off recorded run, not the authoritative verdict, which stays /specclaw:verify's job. Use whenever you need runnable E2E coverage for a target application's real user-facing flows.
---

# specclaw bf-e2e

**First, run** `specclaw-ensure-init .specclaw` — idempotently creates `.specclaw/` if it doesn't exist (silent if already initialized).

Generate E2E test coverage for a target application, driven by a universal E2E automation architect agent. Read-only side-command — no `specclaw-validate-change` call, no `<change>` involved, matching the `analyze`/`bf-architecture`/`bf-baseline` pattern.

1. **Resolve the target path.** If the user's message names a path, use it (validate it exists and is inside the repo). Otherwise default to the repository root.

2. **Check for prior context** (soft — pass the path if present, don't fail if absent):
   ```bash
   [ -f .specclaw/analysis/codebase-report.md ] && echo present
   ```
   This is the only prior-analysis document this command reads. It runs independently of `/specclaw:bf-baseline` — no fixture check, and no `.specclaw/baseline/` document of any kind is read or passed to the agent.

3. **Archive the prior E2E report, if any**, before writing a new one:
   ```bash
   mkdir -p .specclaw/e2e/archive
   mv .specclaw/e2e/e2e-report.md .specclaw/e2e/archive/$(date +%Y-%m-%d-%H%M%S)-e2e-report.md
   ```
   Skip this step if `.specclaw/e2e/e2e-report.md` doesn't exist yet. Same shared-archive convention `skills/bf-architecture/SKILL.md` uses for `architecture.md`.

4. **Spawn the automation agent:** `Agent` tool, `subagent_type: "bf-e2e-architect"`, on the model from `config.yaml` `models.coding` (default: `anthropic/claude-sonnet-5`) — this agent writes real, runnable test code, the same routing as build's coding agents, not the read-only analysis agents. Pass as context:
   - The resolved target path.
   - The resolved path of `codebase-report.md`, if present (Step 2).
   - The resolved path to write the report to (`.specclaw/e2e/e2e-report.md`) and the resolved template path (`$CLAUDE_PLUGIN_ROOT/templates/e2e-report.md`).
   - Any flow/feature description the user included in their invocation of this skill — this is the agent's primary steer for which scenarios to cover (its Task 4); when none is given, the agent derives scenarios itself from the application's own most significant real flows.

5. The agent detects platform/stack, selects the E2E framework, and writes the page object(s), test script(s), and the E2E Test Report itself, per its own Output section — this skill does not write any file itself.

6. **Relay the agent's full response to the user as-is** — it already carries the required Detection Summary → Setup/Execution Commands → Page Object File(s) → E2E Test Script(s) structure. Do not summarize it away; the human needs the actual generated code and commands, not a paraphrase. After relaying it, state that the report was persisted to `.specclaw/e2e/e2e-report.md`.

7. **Execute the generated suite once, to record real numbers** — skip this step only if the user's invocation explicitly says not to run the tests (e.g. "generate only", "don't run them"); otherwise:
   ```bash
   specclaw-bf-e2e-run run .specclaw
   ```
   This runs the agent's `install_cmd` from `.specclaw/e2e/run-config.json` (Task 6 of the agent), then brings up every declared background service — backend APIs, frontend dev/build servers, and dependencies like a database or queue — that its own `check_cmd` says isn't already running, one at a time in the declared order, waiting for each to report ready before starting the next. A service already running when this step starts is left exactly as it is; only services this step itself started are torn down again once `test_cmd` finishes. It then runs `test_cmd`, copies whatever on-failure screenshots/video the run produced (`run-config.json`'s `artifacts_dir`, wired up per the agent's Failure Capture task) into `.specclaw/e2e/artifacts/`, and mechanically patches the report's Execution Results and Artifacts sections — the real Pass Count, Fail Count, Skipped Count, Pass Percentage, Execution Time, and a listing of every captured file — never a number or a file the agent guessed. As its last step it renders `.specclaw/e2e/e2e-report.html` from the now-finished markdown — a mechanical transform, never a second place content is authored, so the two files can never disagree. This step has real side effects (it may install dependencies and start one or more services) and never fails the overall `/specclaw:bf-e2e` run: a missing precondition, a failed install, a service that never becomes ready, or an unparseable test-runner output is recorded in the report (and the HTML rendered from it) as "not executed" or "NOT MEASURED" with its reason, not treated as an error. Relay its one-line summary (or its "not executed" reason) to the user after the report-persistence line from Step 6, and mention the HTML report's path.

## What this command does and does not do

`/specclaw:bf-e2e` never assumes a platform, language, or E2E framework in advance — every detection and every tool selection is derived from evidence the agent gathers from the target repo itself, in that run. It runs entirely independently of `/specclaw:bf-baseline`: it reads no fixture, no `.specclaw/baseline/` document of any kind, and asserts only against business rules and flows the agent actually found in the application's own source (or was explicitly told about) — never a captured Golden Master recording. It never modifies existing application source files, and it never fabricates an expected outcome or a test-execution count — a flow that cannot be driven through the available UI/API surface, or one with no traceable evidence behind it, is reported as a gap, and a test-runner output this can't parse is reported as NOT MEASURED, never silently guessed.

Its own Step 7 execution is a single recorded run for the report, not a lifecycle gate: it carries no acceptance/rejection semantics, blocks nothing, and is not what `/specclaw:pr`'s test policy or the `loop` guardrails read. `/specclaw:verify`, run against a `<change>`, remains the one authoritative verdict elsewhere in the lifecycle.
