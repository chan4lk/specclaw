# Spec: specclaw-dash — one read-only pane for the build, review and learning loops and token use

**Change:** 062-dash-pane
**Size:** architectural
**Depends on:** 059-core-records-suggest (the `lesson` timeline line, `lib/plugins.sh`)

## Decisions taken at approval

- **D-1 Incremental scan.** Transcripts are scanned incrementally by file offset (open question 1).
- **D-2 Tokens and cost.** The pane shows tokens **and** an API-equivalent cost, always labelled
  "API-equivalent estimate" (open question 2).
- **D-3 Install check.** `specclaw-dash` ships no command. The core install check also finds a plugin by its
  folder (`<plugin>/.claude-plugin/plugin.json` next to core, or in the plugin cache). This is smaller than
  shipping a `bin/specclaw-dash` that nothing else needs.
- **D-4 Claude Code only.** Mods do not run in Codex, so `specclaw-dash` has no Codex manifest and no entry in
  `.agents/plugins/marketplace.json`.

## Functional requirements

- **FR-1** A new plugin `plugins/specclaw-dash/` with a Claude manifest at the shared version, a mod
  (`hooks/mod.json` → `hooks/register.tsx`), pure view functions in `hooks/core/`, a README, an entry in
  `.claude-plugin/marketplace.json` and a row in the root README plugin table.
- **FR-2** `/dash` opens a pane `dash` with five parts, in this order:
  1. **Build loop** — one row per active change in `.specclaw/changes/NNN-*`: name, phase, tasks
     done/total (failed), the open timeline span and how long it has run, verdict, PR. Then one fleet line from
     `.specclaw/fleet/report.json`: running jobs, open PRs, jobs, snapshot age.
  2. **Review loop** — per active change with `review/round-*.json`: rounds, the last round's status and
     blocker/major/minor counts, escalations, and the last final pass's head compared with the checkout's `HEAD`
     (`at HEAD` or `behind HEAD`).
  3. **Learning loop** — `lesson` lines from the active changes' `timeline.jsonl` (count by category, the latest
     three), and the count of proposed rules awaiting approval from the specclaw-review MCP tool `learn_propose`.
  4. **Tokens** — from transcripts under `<claude config dir>/projects/<the cwd, every non-alphanumeric
     character replaced by ->`, written in the last 7 days: today's (UTC) tokens and cost, the 7-day tokens and cost, the
     top sessions (name, cost, context used of the 1M window) and the cost per agent role (subagent type). Every
     cost carries the words "API-equivalent estimate".
  5. **Status** — a band above the prompt `dash · <n> building · <n> in review · $<today> today, API-equivalent
     estimate`, and a status-line entry `dash: <n> building · $<today> today (API-equivalent estimate)`.
- **FR-3** The scanner reads counts, model names, ids, titles and agent type/description only. It never keeps
  or shows prompt text, tool input or output, or thinking text.
- **FR-4** The scanner keeps a per-file offset. A file whose size and mtime are unchanged is not read again; a
  grown file is parsed from the offset; a shorter file is parsed again from the start. A half-written last line
  waits for the next refresh.
- **FR-5** Cost per call = list price × (input + 1.25 × 5-minute cache write + 2 × 1-hour cache write) +
  output price × output + cache-read price × cache read, per million tokens. An unlisted model is priced as
  the dearest listed one. A message id counts once in today's total across files.
- **FR-6** A missing source shows an install card instead of its section:
  no `.specclaw/` → install specclaw; no fleet report → install specclaw-fleet / `specclaw-fleet report --save`;
  no review rounds and the review MCP server unreachable → install specclaw-review; no transcript folder → a
  "no transcripts" card naming the folder.
- **FR-7** A failed read shows an error line for that section and none of its numbers. A record that does not
  parse is counted (`n unreadable records`), never guessed at. A transcript over the 4 MiB read limit is skipped
  and counted, and the token totals are then shown with `≥` as a lower bound.
- **FR-8** The pane is read only: it never writes a file and never runs a command. No launch, approve or caps
  action (063).
- **FR-9** The pane refreshes at session start, on `/dash`, after each turn, and after a tool call that
  mentions `.specclaw`.
- **FR-10** 059 follow-up: `dash` is a feature in `plugins/specclaw/lib/plugins.sh`; the status skill (lean and
  full) calls `specclaw-suggest .specclaw dash` when a change is in build or verify; the install check finds
  `specclaw-dash` by its folder (D-3).

## Non-functional requirements

- **NFR-1** Pure logic in `hooks/core/*.ts` with bun specs over fixture transcripts; the real hooks are driven by
  `claude plugin test`; `claude plugin validate` passes.
- **NFR-2** All plugins stay on one version (R1). The split and Codex packaging tests still pass.
- **NFR-3** No new dependency.

## Acceptance criteria

- **AC-1** `claude plugin validate plugins/specclaw-dash` passes, the marketplace lists `specclaw-dash` at the
  shared version, and the README table has its row. (FR-1, D-4)
- **AC-2** Fixture transcripts give exact token counts, cost, context, session names and per-role totals; a
  repeated message id is counted once; prompt, tool and thinking text never appear in the scan result.
  (FR-2.4, FR-3, FR-5)
- **AC-3** A grown file is parsed from its offset (earlier lines are not parsed again); a shorter file is
  parsed from 0; a half line is held back; a bad record is counted. (FR-4, FR-7)
- **AC-4** Build, review and learning parts render from fixture change folders: phase, tasks, open span,
  round counts, escalations, final pass at or behind HEAD, lessons. (FR-2.1–2.3)
- **AC-5** Each missing source shows its install card; each failed read shows an error line and no numbers;
  a skipped big transcript shows `≥`. (FR-6, FR-7)
- **AC-6** `/dash` opens the pane; the band and the status line show the FR-2.5 text; every cost string in the
  pane, band and status contains "API-equivalent estimate". (FR-2.5, D-2)
- **AC-7** The mod has no `$.fs.write` and no `$.process` call. (FR-8)
- **AC-8** `specclaw-suggest .specclaw dash` prints the dash tip when the plugin folder is absent and nothing
  when `specclaw-dash/.claude-plugin/plugin.json` sits next to core or in the cache; both status skills name the
  call. (FR-10)

## Edge cases

- A change with no `state.json`, no tasks, or an unparseable `state.json` (phase `?`).
- `escalated` recorded as a list (older rounds) or a number (newer rounds).
- `.git` as a file (worktree: `gitdir:` with `commondir`), a detached `HEAD`, a ref only in `packed-refs`.
- A transcript record whose usage count is not a whole number, a missing model, or a non-object `.meta.json`.
- A subagent transcript under `<session>/subagents/agent-<id>.jsonl` with its `.meta.json`.
