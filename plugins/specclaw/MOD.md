# specclaw mod

The specclaw plugin includes a [Claude Code mod](https://code.claude.com/docs/en/plugins/mods/overview). It reads `.specclaw/changes/*/` in the session's working directory and adds:

| Feature | What it shows or does |
|---|---|
| `/specclaw-pane` | A pane beside the chat with one row per active change: name, phase, tasks done/total, failed count, verify verdict and PR link. |
| Band above the prompt | `specclaw · <change> · <phase> · <done>/<total> tasks` for the change whose `state.json` changed most recently. |
| Status line | `specclaw: <n> active`, plus `· building <NNN>` while a change is in `build`. |
| Branch guard | The propose gate also holds an edit to a project file outside `.specclaw/` and `.git/` while the checkout is on the base branch, even when a change is approved: `specclaw: main is the base branch. Create a change branch first before editing <file>.` |
| Propose gate | Checks `Edit`, `Write` and `NotebookEdit` on files inside the project but outside `.specclaw/` and `.git/` when no active change has an approved proposal: a toast in `warn` mode (the default), a denial in `block` mode. Edits to a change's `state.json` are checked too, so the model cannot approve its own proposal with an edit. So are writes that would replace `.specclaw/`, `.specclaw/changes/` or a change's `state.json`, `tasks.md` or `change.md` with something the mod can no longer read, such as `tasks.md/x`. |

The mod refreshes its view at session start, after every turn, and after any tool call that mentions `.specclaw`. It never writes to `.specclaw/`.

## Install

Installing specclaw installs the mod. There is nothing else to add:

```
/plugin install specclaw@chan4lk
```

Claude Code loads the mod from `hooks/mod.json`, which `.claude-plugin/plugin.json` names. It is not in `hooks/hooks.json`, because Codex reads that file and refuses unknown keys.

The mod needs Claude Code 2.1.287 or later. Older versions skip the mod and run the rest of specclaw as usual (checked on 2.1.250). Mods do not run in Codex.

## Propose gate

Set `gate` in the plugin's config (`/plugin`, then the plugin's options) to:

- `warn` (default): allow the edit and show `specclaw: no approved change is open. Run /specclaw:propose and get approval before editing <file>.` as a toast.
- `block`: deny the edit with that message.
- `off`: no check.

Case and surrounding spaces are ignored. Any other value is read as `warn`, and a toast at session start names the value.

### Branch guard

The base branch is `git.base_branch` in `.specclaw/config.yaml`, else `origin/HEAD`, else `main`. The current branch is read from the session's working directory with `git branch --show-current`. The guard follows the gate's mode (`warn`, `block`, `off`). Outside git, on a detached HEAD, or when `git` fails, it does not check.

If the gate itself fails (for example, it cannot read `.specclaw/`), it allows the edit and shows a toast, in every mode. This is deliberate: a broken gate must never stop work.

**Known gaps:**

- Any approved change that has not been archived unlocks edits. Archive merged changes to keep the gate meaningful.
- File writes through `Bash` (`sed -i`, redirects) are not checked.
- `.specclaw/` is looked up only in the session's working directory, not in parent folders.
- Paths are resolved through the file system before they are compared, so symbolic links and the letter case of existing folders resolve. The `state.json` check ignores case, so a new `State.json` is held too. A spelling that cannot be resolved, such as a `\\?\` or UNC prefix, a drive-relative path or a `:` stream name, is held as if it were inside the project.

## Done guard

`hooks/done-guard` is a `Stop` command hook, registered in `hooks/mod.json`, so it runs in Claude Code only. For each active change touched on this branch (since the merge-base with the base branch) whose tasks are all done, it names each missing step on stderr and exits 2, which keeps the turn going:

- no verify verdict, or one that is not PASS;
- code outside `.specclaw/` committed after the verify verdict, or uncommitted or untracked changes outside `.specclaw/` (a verdict with no time cannot be tied to HEAD either);
- when `specclaw-review` is on PATH, a review verdict that is not clean.

It exits 0 when a Stop is already held by it (`stop_hook_active`), when the project has no `.specclaw/config.yaml`, and on any internal error. An internal error is not silent: the guard prints a `systemMessage` naming it (`specclaw: the done guard did not run (<error>), so nothing was checked.`), which Claude Code shows without blocking the turn. A change the guard cannot check (for example, a tasks file it cannot count) goes through one `skip` function, which always names the change and the reason to the user: in that `systemMessage`, or on stderr next to the held steps when another change is held. It is not registered in `hooks/hooks.json`: Codex reads that file, and nothing shows that Codex accepts a `Stop` command hook.

`hooks/context-gate` is a `PreToolUse` command hook, also registered in `hooks/mod.json` only (change 065). It holds a subagent to its role's context cap: at 90% it tells the agent to commit and hand off (`budget.gate: warn`, shipped) or denies all but committing (`block`). The main session is never capped, and any error lets the call through with a `systemMessage`. See `CLAUDE.md`, "The context gate".

## Development

```
bash plugins/specclaw/tests/run-mod-tests.sh
```

This runs the bun tests for the pure logic in `hooks/core/` and the kit tests in `tests/*.test.ts`, then `claude plugin validate` and `claude plugin test` (which drives the real hooks). It needs `bun` and `claude` on PATH. To try the mod in a session, start one with `claude --plugin-dir plugins/specclaw`.
