# Proposal: Keep specclaw's hooks.json readable by Codex

**Created:** 2026-11-03
**Status:** ✅ Approved

## Problem

0.8.6 (change 047) added `"modules": ["./register.tsx"]` to `plugins/specclaw/hooks/hooks.json`. Codex reads that same file and rejects it:

```
warning: failed to parse plugin hooks config .../specclaw/0.8.6/hooks/hooks.json: unknown field `modules`, expected `description` or `hooks` at line 15 column 11
```

So Codex users of 0.8.6 lose specclaw's SessionStart hook, which injects the intent router and the live state block. Nothing tested Codex's reading of `hooks.json`, so CI was green.

## Proposed Solution

1. Remove `modules` from `plugins/specclaw/hooks/hooks.json`. It keeps only the SessionStart hook, which both hosts read.
2. Put the mod in a new `plugins/specclaw/hooks/mod.json` (`{"modules": ["./register.tsx"]}`), and name it only in `.claude-plugin/plugin.json` as `"hooks": "./hooks/mod.json"`. Codex reads only `hooks/hooks.json`, so it never sees the mod.

   This was checked in a scratch copy on Claude Code 2.1.317. `claude plugin validate` finds the module through the manifest path, and `claude plugin test` passes. A live session runs both the router from `hooks/hooks.json` and the mod.
3. Add a regression check: every `plugins/*/hooks/hooks.json` may hold only the keys Codex accepts (`description`, `hooks`). It goes in an existing registered suite (`run-codex-plugin-tests.sh`), so CI catches this next time.
4. Docs (`MOD.md`, the plugin `CLAUDE.md` session-bootstrap section, `context.md` constraint) say where the mod is loaded from and why.
5. Bump all plugins to 0.8.7 and cut a release, so Codex and Claude installs can upgrade again.

## Scope

### In Scope
- `plugins/specclaw/hooks/hooks.json`, new `plugins/specclaw/hooks/mod.json`, `plugins/specclaw/.claude-plugin/plugin.json`
- the hooks.json key check in `plugins/specclaw/tests/run-codex-plugin-tests.sh`
- `MOD.md`, `plugins/specclaw/CLAUDE.md`, `.specclaw/context.md`
- version bump to 0.8.7

### Out of Scope
- Any change to the mod's behaviour.
- Codex support for the mod itself (mods do not run in Codex).
- PR #104 (archive 041–046), which stays separate.

## Impact

- **Size:** bounded (spike / bounded / architectural) — it alters where an existing hooks file loads from; no new subsystem.
- **Files affected:** ~7 (estimated)
- **Complexity:** small (small / medium / large)
- **Risk:** low (low / medium / high) — the layout was tried in a scratch copy on both the router and the mod. The remaining risk is older Claude Code clients reading a manifest `hooks` path; the 2.1.250 load check from 047 is re-run.

## Open Questions

- None blocking. The upgrade of every install is paused until this ships; Claude installs are already at 0.8.6 and work, and Codex installs are at 0.8.6 with the router missing.
