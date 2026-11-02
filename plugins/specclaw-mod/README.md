# specclaw-mod

A [Claude Code mod](https://code.claude.com/docs/en/plugins/mods/overview) for specclaw. It reads `.specclaw/changes/*/` in the session's working directory and adds:

| Feature | What it shows or does |
|---|---|
| `/specclaw-pane` | A pane beside the chat with one row per active change: name, phase, tasks done/total, failed count, verify verdict and PR link. |
| Band above the prompt | `specclaw · <change> · <phase> · <done>/<total> tasks` for the change whose `state.json` changed most recently. |
| Status line | `specclaw: <n> active`, plus `· building <NNN>` while a change is in `build`. |
| Propose gate | Denies `Edit`, `Write` and `NotebookEdit` on files inside the project but outside `.specclaw/` and `.git/` when no active change has an approved proposal. |

The mod refreshes its view at session start, after every turn, and after any tool call that mentions `.specclaw`. It never writes to `.specclaw/`.

## Install

```
/plugin install specclaw-mod@chan4lk
```

Requires Claude Code 2.1.287 or later. Older versions ignore the plugin. Mods do not run in Codex.

## Propose gate

Set `gate` in the plugin's config (`/plugin`, then the plugin's options) to:

- `block` (default): deny the edit with `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing <file>.`
- `warn`: allow the edit and show that message as a toast.
- `off`: no check.

If the gate itself fails, it allows the edit and shows a toast.

**Known gaps:**

- Any approved change that has not been archived unlocks edits. Archive merged changes to keep the gate meaningful.
- File writes through `Bash` (`sed -i`, redirects) are not checked.
- `.specclaw/` is looked up only in the session's working directory, not in parent folders.

## Development

```
bash plugins/specclaw-mod/tests/run-mod-tests.sh
```

This runs the bun tests for the pure logic in `hooks/core/`, and runs `claude plugin validate` when `claude` is on PATH. To try the mod in a session, start one with `claude --plugin-dir plugins/specclaw-mod`.
