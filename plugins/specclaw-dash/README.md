# specclaw-dash

A [Claude Code mod](https://code.claude.com/docs/en/plugins/mods/overview) for specclaw projects. It adds one
pane, `/dash`, that shows the build, review and learning loops and the tokens spent, in one place, and offers a
few actions. The mod reads files and never writes one. Each action runs one existing command, and the pane owns
no logic of its own.

## Install

```
/plugin install specclaw-dash@chan4lk
```

Then type `/dash`. The mod needs Claude Code 2.1.287 or later; the actions were tested on 2.1.325. It does not run
in Codex, so its Codex manifest carries metadata only.

## What it shows

| Part | Reads | Shows |
|---|---|---|
| Build | `.specclaw/changes/NNN-*/state.json`, `tasks.md` (or `change.md`), `timeline.jsonl`; `.specclaw/fleet/report.json` | One row per active change: phase, tasks done/total and failed, the open timeline span and how long it has run, verdict, PR. One fleet line: running jobs, open PRs, snapshot age. |
| Review | `changes/*/review/round-*.json`, the checkout's `HEAD` | Rounds, the last round's status and blocker/major/minor counts, escalations, and whether the last final pass is at `HEAD`. |
| Learning | `lesson` lines in `timeline.jsonl`; specclaw-review's `learn_propose` MCP tool | Lessons by category and the latest three; proposed rules awaiting approval. |
| Tokens | Transcripts under `~/.claude/projects/<this project>` (or `$CLAUDE_CONFIG_DIR/projects/...`) from the last 7 days | Today (UTC) and 7-day tokens and cost, the top sessions with their context used, and cost by agent role. |
| Band and status line | the above | `dash · <n> building · <n> in review · $<today> today, API-equivalent estimate` |

## Actions

Each action runs one existing command through the Bash tool. That tool has the plugins' `bin/` folders on
`PATH`, and your permission rules decide whether the command runs. When no rule allows it (for example in default
mode), the pane puts the exact command into the prompt for you to send. The pane shows each command, its exit
code and the end of its output.

| Action | Command |
|---|---|
| **Launch:** pick approved changes (before build, no PR) or `**Feature:**` modules, then **Dry run** | `specclaw-fleet optin <items> --dry-run` |
| **Confirm launch:** shown only after a dry run of exactly the selection | `specclaw-fleet optin <ok> && specclaw-fleet trigger <change> … && specclaw-fleet feature start <module>` |
| **Approve** / **Reject** a rule `learn` proposes | `specclaw-review learn --apply <fp>` / `specclaw-review learn --reject <fp>` |
| **Show caps**, then type a new cap and press Enter | `specclaw-budget roles --json <dir>` / `specclaw-budget set <dir> <role> <n>` |
| **Show dismissed**, then **Undo** | `specclaw-suggest <dir> --dismissed` / `specclaw-suggest <dir> --undismiss <feature>` |

- **Launch follows fleet's consent rule.** `optin` runs as the identity behind your own `AZDO_TOKEN`. It assigns
  each item to you and adds `fleet:auto` as you, and it refuses an item assigned to someone else. Confirm offers
  only the items the dry run did not refuse, and `trigger` checks consent again before it spends your plan. Confirm
  spends your plan and pushes a branch. Without specclaw-fleet, or with fleet not set up, Launch shows how to set
  it up and offers no Confirm.
- **Caps** need `specclaw-budget` (the context-gate release, change 065). Without it the part shows one note
  and no controls. The pane never writes `config.yaml`; `specclaw-budget set` checks the range.
- A rejected rule is not proposed again. Its lesson stays in review memory.
- Every value put into a command (change, module, fingerprint, role, number, feature) must match a fixed
  pattern, or the action is refused before anything runs.

**Cost is an API-equivalent estimate:** what the same tokens would cost at API list prices. It is not a bill,
and on a subscription plan it is not what you pay. Prices are in `hooks/core/scan.ts`.

**Privacy.** The transcript scanner keeps counts, times, ids, model names, session titles, git branch names and agent types.
It never keeps or shows prompt text, tool input or output, or thinking text.

**Missing and failed sources.** A source that is not there shows an install card (for example, no fleet report
shows how to install specclaw-fleet). A read that fails shows one `error:` line for that part and none of its
numbers. A record that does not parse is counted, never guessed at.

**Known limits:**

- A mod can read at most 4 MiB of a file. A longer transcript is not counted. The pane says how many, and marks
  every total with `≥` as a lower bound.
- Transcripts are scanned incrementally: an unchanged file is not read again, and a grown file is parsed only
  from where the last scan stopped. A reload of the mod starts the scan over.
- `/specclaw-pane` (core) and `/fleet-pane` (fleet) stay as they are.
- Local (non-fleet) headless runs are not an action. Use `/specclaw-extras:auto`.

## Development

```
bash plugins/specclaw-dash/tests/run-mod-tests.sh
```

This runs the bun specs for `hooks/core/` (the scanner on small fixture transcripts, the loop parsers and the
view and the action commands), checks that the mod has no file write or process call and that its only tool call
is Bash in `hooks/act.ts`, then runs `claude plugin validate` and `claude plugin test`. Run the specs as `bun test ./tests/*.spec.ts`: a bare `bun test` also picks up
`pane.test.tsx`, which only `claude plugin test` can run. To try it in a session: `claude --plugin-dir plugins/specclaw-dash`.
