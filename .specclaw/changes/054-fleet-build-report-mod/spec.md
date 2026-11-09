# Spec: specclaw-fleet build report and mod

**Change:** 054-fleet-build-report-mod
**Created:** 2026-11-09
**Size:** architectural

## Functional Requirements

- **FR-1 Durable run fields.** Fields are added to the existing run-update comments. No existing key changes.
  - **Dispatch** (`launch.sh`): `pipeline_run=<BUILD_BUILDID>`, or `local` outside a pipeline.
  - **Pod** (`entrypoint.sh`), on the final record, before `agent.log` is cut down for display:
    - `agent_started` and `agent_ended`: UTC ISO times;
    - `agent_s`: whole seconds;
    - `cost_usd`, `turns` and `model`: from `total_cost_usd`, `num_turns` and the first `modelUsage` key of the last JSON object in `agent.log`. Each is omitted when it cannot be read (Codex, non-JSON output, or a crash);
    - `review_rounds`: the count of `review/round-*.json` in the change folder;
    - `agent_commits`: `git rev-list --count <built_commit>..HEAD`.
  - The PR number is already in `pr=`.
- **FR-2 `specclaw-fleet report [<change>...|--feature <m>] [--since ISO] [--json] [--html <file>] [--save]`.** Read-only toward AzDO and the cluster.
  - **Scope:**
    - named changes;
    - or the members of feature `<m>`, each with its wave from the feature graph;
    - or, by default, every approved change that has at least one run record.
  - **Run:** a change's run is its newest `state=dispatched` record and every record after it. Newer values win.
  - **`--since`** drops runs dispatched before that time.
  - **Gap fill, each best-effort:**
    - **PR** (`git/pullrequests/<id>`): `creationDate`, `closedDate`, `status`.
    - **Pipeline run** (`build/builds/<pipeline_run>`): `queueTime`, `startTime`, `finishTime`.
    - **Cluster** (`status_job`): the live Job phase.
    - A failed read leaves that field empty and never fails the report.
  - **Totals:**
    - `wall_s`: from the earliest queue or dispatch to the latest agent end, PR record or now while running;
    - `jobs`;
    - `agent_s`;
    - `hosted_s` (pipeline finish minus start);
    - `review_rounds`;
    - `commits`;
    - `claude_fetch_s`, as a maximum;
    - `cost_usd`;
    - `running`;
    - `prs_open`.
  - **Output:**
    - **Default:** one table line per change, then a totals block. Cost is labelled `API-equivalent estimate`.
    - **`--json`:** the snapshot document (FR-3) on stdout.
    - **`--html <file>`:** one self-contained page with no network references. It shows the timeline, by wave when known, with a pipeline bar, an agent bar and a PR-open bar per change, plus the lifecycle table and the totals.
    - **`--save`:** writes the snapshot to `$SPECCLAW_DIR/fleet/report.json`, and `$SPECCLAW_DIR/fleet/.gitignore` containing `*`.
  - **Exit status:** 0, or 1 on bad arguments.
- **FR-3 Snapshot v1:** `{version: 1, generated_at, scope, rows: [...], totals: {...}}`.
  - **Each row:**
    - `change`, `work_item`, `wave`, `state`, `exit`;
    - `pipeline_run`, `queued`, `started`, `finished`;
    - `job`, `phase`;
    - `agent_started`, `agent_ended`, `agent_s`, `claude_fetch_s`;
    - `review_rounds`, `agent_commits`, `cost_usd`, `turns`, `model`;
    - `pr`, `pr_status`, `pr_opened`, `pr_closed`.
  - Missing values are `null`.
- **FR-4 Mod** (`plugins/specclaw-fleet/hooks/mod.json`). It reads only `<cwd>/.specclaw/fleet/report.json`, through `$.fs`. It runs no process and makes no network call.
  - **`/fleet-pane`:** opens a pane with:
    - a header: scope, and snapshot age;
    - totals;
    - an ASCII timeline: one row per change, with columns scaled from the earliest to the latest time;
    - the lifecycle table;
    - a footer `Refresh: specclaw-fleet report --save`.
  - **Band:** `fleet · <n> running · <m> PRs open · last run HH:MM UTC`. It is hidden when there is no snapshot.
  - **Status line:** `fleet: <n> running`. It is cleared when there is no snapshot.
  - **Refresh:** at session start, on `/fleet-pane`, and after a Bash tool call whose command matches `specclaw-fleet (trigger|status|report)`.
  - An unreadable or wrong-version snapshot shows `fleet · report unreadable` and never throws.
- **FR-5 Skill `/specclaw-fleet:report`:** runs `report --save` for the scope asked, plus `--html` when asked, then tells the user to open `/fleet-pane`, and summarises the totals in at most 5 lines.

## Non-Functional

- Shell: ShellCheck clean, files of 80 lines or fewer, no comments except pragmas.
- TypeScript: pure logic in `hooks/core/`, tested by bun.
- One test per AC; table-driven variants where the input has variants.

## Acceptance Criteria

- **AC-1:** Dispatch records `pipeline_run`. The final pod record carries `agent_started`, `agent_ended` and `agent_s`, plus `cost_usd`, `turns` and `model` when `agent.log` ends in result JSON. The cost keys are absent for non-JSON output, and `review_rounds` and `agent_commits` are present. Covered by table-driven tests over the log variants.
- **AC-2:** `report --json` builds rows and totals from stubbed records, PRs, builds and cluster. A failed PR, build or cluster read gives empty fields and exit 0. `--since` and `--feature` scope correctly. Covered by a table-driven test.
- **AC-3:** `report` (table), `--html` (self-contained, with no `http` URL other than the PR links) and `--save` (snapshot plus `.gitignore`) write the expected outputs.
- **AC-4:** Mod core: parse, validate the version, timeline scaling, pane lines, band text and status text are correct for an empty snapshot, an unreadable snapshot, one running row, and mixed rows (bun spec).
- **AC-5:** Mod wiring: `claude plugin validate` passes. `claude plugin test` shows the pane renders from a seeded snapshot, and a Bash `specclaw-fleet report` call refreshes the band.
- **AC-6:** The skill, the README section and the CI step exist, and the fleet test suite registers the new cases.

## Edge Cases

- A change with records only from before this change has no agent times. Fall back to the `running` record's `at` and the `pr_open`/`failed` record's `at`.
- A run is still going: the end is `generated_at`, and the row phase comes from the cluster.
- A PR id cannot be parsed from `pr=none`: the PR fields are null.
- A snapshot older than 24h shows its age in the pane header.
