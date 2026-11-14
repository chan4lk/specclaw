# Spec: Keep specclaw's hooks.json readable by Codex

**Change:** 048-codex-safe-mod-hooks
**Size:** bounded

## Requirements

- **FR-1:** `plugins/specclaw/hooks/hooks.json` holds only keys Codex accepts (`description`, `hooks`) and still registers the SessionStart hook.
- **FR-2:** Claude Code loads the mod from `plugins/specclaw/hooks/mod.json`, which `.claude-plugin/plugin.json` names as `"hooks": "./hooks/mod.json"`. The mod's behaviour does not change.
- **FR-3:** a registered test fails when any `plugins/*/hooks/hooks.json` has a key other than `description` or `hooks`.
- **FR-4:** all plugin versions move to 0.8.7 (review rule R1).

## Acceptance Criteria

- **AC-1:** `hooks/hooks.json` parses, has only `hooks` at the top level, and its SessionStart command is unchanged.
- **AC-2:** `claude plugin validate plugins/specclaw` passes and lists `./register.tsx` hooks; `run-mod-tests.sh` passes.
- **AC-3:** `run-codex-plugin-tests.sh` passes, and fails with a named message when `modules` is put back into `hooks/hooks.json`.
- **AC-4:** a Codex session using the change's `hooks/hooks.json` prints no `failed to parse plugin hooks config` warning for specclaw.
- **AC-5:** a Claude Code 2.1.250 session still loads the plugin (skills and router).
- **AC-6:** `MOD.md`, `plugins/specclaw/CLAUDE.md` and `.specclaw/context.md` name `hooks/mod.json` and say why it is separate.

## Approach

One decision: the mod's `modules` entry moves out of the file both hosts read into a file only the Claude manifest names. Claude Code still reads the default `hooks/hooks.json` as well (checked live: the router and the mod both ran from a scratch copy).

File map:
- `plugins/specclaw/hooks/hooks.json` — drop `modules`
- `plugins/specclaw/hooks/mod.json` — new, `{"modules": ["./register.tsx"]}`
- `plugins/specclaw/.claude-plugin/plugin.json` — `"hooks": "./hooks/mod.json"`, version
- `plugins/specclaw/tests/run-codex-plugin-tests.sh` — hooks.json key check
- `plugins/specclaw/MOD.md`, `plugins/specclaw/CLAUDE.md`, `.specclaw/context.md` — docs
- every other `plugins/*/.c*-plugin/plugin.json`, `.claude-plugin/marketplace.json` — version
