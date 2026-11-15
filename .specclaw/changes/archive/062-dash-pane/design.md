# Design: specclaw-dash

## Approach

Follow the two mods already in the repo. `specclaw-fleet` gives the shape: `register.tsx` registers the command
and the `ui.render` hooks, one module does the `$.fs` reads and keeps one atom, and `hooks/core/` holds pure
functions that the bun specs test. Plugins install into separate cache folders, so dash cannot import core's
or fleet's `hooks/core/*.ts`; it carries its own small parsers (task count, fleet report totals).

```
session.start / /dash / turn.complete / tool.call(.specclaw)
        │
        ▼
 read.ts  ── $.fs.list/stat/read, $.env.get, $.mcp.call (learn_propose)  ── raw text only
        │
        ▼
 core/loops.ts   build + review + learning from change folders (pure)
 core/scan.ts    transcript scanner: offset state per file → calls (pure)
 core/view.ts    paneLines / bandText / statusText (pure)
        │
        ▼
 atom 'dash/view'  ──►  Pane `dash`, AbovePrompt band, $.ui.status
```

## Key decisions

1. **Offsets over a whole-file read.** `$.fs.read` returns a whole file and refuses one over 4 MiB, so
   "incremental" means: skip a file whose size and mtime did not change (from `$.fs.list`), and parse a grown
   file only from the stored character offset. The scan state lives in a module variable; a reload starts it
   over (a full rescan), which is correct, only slower once.
2. **Big transcripts are skipped and counted.** A file over 4 MiB cannot be read by a mod. It is left out,
   counted, and the totals show `≥`. `shortcut: main-session transcripts over 4 MiB are not counted; upgrade
   when the engine offers a ranged read`. Running `tail -c` through `$.process` would break FR-8.
3. **Each section carries its own state** `{ kind: 'ok' | 'missing' | 'error' }`. An error never keeps old
   numbers: it renders one error line. That is how "never shown as live data" holds without a stale cache.
4. **Prices** are copied from the claude-api skill (cached 2026-11-03) into `core/scan.ts`, per million tokens
   (input, output, cache read): opus-5-5 4/20/0.20, opus-5 5/25/0.50, sonnet-5-5 2/10/0.10, sonnet-5 2/10/0.20,
   fable-5-2 8/40/0.20, fable-5-1 10/50/0.25, haiku-5-5 0.10/0.50/0.01. A dated or suffixed id
   (`claude-opus-5-5[1m]`) matches by prefix; an unknown model costs as fable-5-1, the dearest.
5. **Proposed rules come through the MCP server**, not by reading `findings.jsonl`: review memory is reached
   only through specclaw-review's CLI or MCP (`review_memory.py` header). `learn_propose` returns
   `N proposed rule(s)…` or `no recurring lessons…`; any other answer or a failed call is an error line, and an
   unreachable server with no review rounds is the install card.
6. **HEAD** is resolved from files: `.git` (dir, or `gitdir:` file for a worktree, with `commondir`), `HEAD`,
   the loose ref, then `packed-refs`. Pure resolver over a read function, so it is tested without git.
7. **Install check by folder (D-3).** The `dash` row in `lib/plugins.sh` has an empty command field. For such a
   row, `installed()` looks for `<plugin>/.claude-plugin/plugin.json` beside core (checkout) or in
   `<cache>/<owner>/<plugin>/*/` (cache). Rows with a command keep the command checks unchanged.

## File changes

| File | Change |
|---|---|
| `plugins/specclaw-dash/.claude-plugin/plugin.json` | new manifest (`hooks: ./hooks/mod.json`, `types`) |
| `plugins/specclaw-dash/hooks/mod.json`, `register.tsx`, `read.ts` | new mod: command, pane, band, status, refresh |
| `plugins/specclaw-dash/hooks/core/{loops,scan,view}.ts` | new pure logic |
| `plugins/specclaw-dash/types/index.d.ts` | atom contract |
| `plugins/specclaw-dash/tests/*.spec.ts`, `pane.test.tsx`, `fixtures.ts`, `run-mod-tests.sh` | tests |
| `plugins/specclaw-dash/README.md` | what it shows, install, development |
| `.claude-plugin/marketplace.json`, `README.md` | new entry, table row |
| `.github/workflows/ci.yml` | run the dash mod tests |
| `plugins/specclaw/tests/run-plugin-split-tests.sh` | AC-7 knows dash is Claude-only |
| `plugins/specclaw/lib/plugins.sh`, `bin/specclaw-suggest` | `dash` feature, install check by folder |
| `plugins/specclaw/skills/status/SKILL.md`, `references/full/status.md` | suggest call site |
| `plugins/specclaw/tests/run-suggest-tests.sh` | AC-8 |

## Risks

- **Large histories.** Every refresh lists the transcript folder and each session's `subagents/` folder. Reads
  are limited to changed files from the last 7 days.
- **Transcript format drift.** A record that does not match is counted as unreadable and shown, not guessed.
- **A slow MCP server** would delay a refresh. `learn_propose` is a local stdio call made on every refresh, so
  the count is never older than the rest of the pane.
