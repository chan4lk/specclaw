# specclaw mod

The specclaw plugin includes a [Claude Code mod](https://code.claude.com/docs/en/plugins/mods/overview). It reads `.specclaw/changes/*/` in the session's working directory and adds:

| Feature | What it shows or does |
|---|---|
| `/specclaw-pane` | A pane beside the chat with one row per active change: name, phase, tasks done/total, failed count, verify verdict and PR link. |
| Band above the prompt | `specclaw · <change> · <phase> · <done>/<total> tasks` for the change whose `state.json` changed most recently. |
| Status line | `specclaw: <n> active`, plus `· building <NNN>` while a change is in `build`. |
| Propose gate | Checks `Edit`, `Write` and `NotebookEdit` on files inside the project but outside `.specclaw/` and `.git/` when no active change has an approved proposal: a toast in `warn` mode (the default), a denial in `block` mode. Edits to a change's `state.json` are checked too, so the model cannot approve its own proposal with an edit. So are writes that would replace `.specclaw/`, `.specclaw/changes/` or a change's `state.json`, `tasks.md` or `change.md` with something the mod can no longer read, such as `tasks.md/x`. |

The mod refreshes its view at session start, after every turn, and after any tool call that mentions `.specclaw`. It never writes to `.specclaw/`.

## Install

Installing specclaw installs the mod. There is nothing else to add:

```
/plugin install specclaw@chan4lk
```

The mod needs Claude Code 2.1.287 or later. Older versions skip the mod and run the rest of specclaw as usual. Mods do not run in Codex.

## Propose gate

Set `gate` in the plugin's config (`/plugin`, then the plugin's options) to:

- `warn` (default): allow the edit and show `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing <file>.` as a toast.
- `block`: deny the edit with that message.
- `off`: no check.

If the gate itself fails (for example, it cannot read `.specclaw/`), it allows the edit and shows a toast, in every mode. This is deliberate: a broken gate must never stop work.

**Known gaps:**

- Any approved change that has not been archived unlocks edits. Archive merged changes to keep the gate meaningful.
- File writes through `Bash` (`sed -i`, redirects) are not checked.
- `.specclaw/` is looked up only in the session's working directory, not in parent folders.
- Paths are resolved through the file system before they are compared, so symbolic links and the letter case of existing folders resolve. The `state.json` check ignores case, so a new `State.json` is held too. A spelling that cannot be resolved, such as a `\\?\` or UNC prefix, a drive-relative path or a `:` stream name, is held as if it were inside the project.

## Development

```
bash plugins/specclaw/tests/run-mod-tests.sh
```

This runs the bun tests for the pure logic in `hooks/core/` and the kit tests in `tests/*.test.ts`, then `claude plugin validate` and `claude plugin test` (which drives the real hooks). It needs `bun` and `claude` on PATH. To try the mod in a session, start one with `claude --plugin-dir plugins/specclaw`.
