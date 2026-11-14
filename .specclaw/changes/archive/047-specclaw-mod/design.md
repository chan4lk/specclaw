# Design: specclaw mod

**Change:** 047-specclaw-mod

## Technical Approach

A new plugin folder holding one Claude Code mod. Logic is split in two so CI can test it without Claude:

- `hooks/core.ts` — pure functions over plain data: `parseState`, `countTasks`, `summarise(changes)`, `currentChange`, `paneRows`, `bandText`, `statusText`, `gateDecision({ cwd, path, hasSpecclaw, changes, mode })`. No `$`, no JSX.
- `hooks/register.tsx` — wiring only: reads files with `$.fs.list/read/stat`, feeds `core.ts`, stores the snapshot in `$.state` (`atom` with a `shape` tag), draws the pane and band, sets `$.ui.status`, registers `/specclaw-pane`, and the gated `tool.call` hook with `.catch` failing open.

## Architecture

```
session.start / turn.complete / tool.call(.specclaw) / command.run
        │
        ▼
  refresh($)  ──$.fs──▶ .specclaw/changes/*/{state.json,tasks.md,change.md}
        │ core.summarise()
        ▼
  $.state 'specclaw-mod'.snapshot ──read──▶ Pane 'specclaw' / AbovePrompt
        └──────────────▶ $.ui.status(core.statusText)

tool.call {Edit|Write|NotebookEdit} ──▶ core.gateDecision(snapshot, options.gate)
        ├─ deny  → { deny: msg }
        ├─ warn  → $.ui.toast(msg); next(e)
        └─ allow → next(e)
```

The gate reads the latest snapshot and, if the snapshot is older than the last `.specclaw` touch, refreshes first, so a just-approved proposal unlocks edits in the same turn.

## File Changes

| File | Change |
|---|---|
| `plugins/specclaw-mod/.claude-plugin/plugin.json` | new — manifest, `userConfig.gate` (string, options block/warn/off, default block), `types` |
| `plugins/specclaw-mod/hooks/hooks.json` | new — `{ "modules": ["./register.tsx"] }` |
| `plugins/specclaw-mod/hooks/core.ts` | new — pure logic |
| `plugins/specclaw-mod/hooks/register.tsx` | new — mod wiring |
| `plugins/specclaw-mod/hooks/place.ts` | new — resolves the gate's target and cwd through `$.fs.stat` realPath (review round 7 redesign) |
| `plugins/specclaw-mod/types/index.d.ts` | new — `PluginState['specclaw-mod']` contract |
| `plugins/specclaw-mod/tsconfig.json` | new — type-check config |
| `plugins/specclaw-mod/tests/core.test.ts` | new — bun tests for AC-1…AC-7 |
| `plugins/specclaw-mod/tests/run-mod-tests.sh` | new — runs bun tests, `claude plugin validate` when available |
| `plugins/specclaw-mod/README.md` | new — what it does, gate switch, version floor, Bash gap |
| `.claude-plugin/marketplace.json` | add entry; bump all versions |
| `plugins/*/.claude-plugin/plugin.json` | version bump |
| `.github/workflows/ci.yml` | register runner (+ setup-bun) |
| `README.md` | one line pointing to the mod |

## Key Decisions

- **Pure core + thin wiring** — the mods test kit needs the `claude` binary; CI has bash and can add bun. Pure functions cover every AC except validate.
- **Snapshot in `$.state`, not module vars** — survives hot reload and drives redraws without `invalidate`.
- **Fail open** — a broken guard must not stop all edits; it toasts instead (operator-confirmed).
- **Resolved paths, not text** — the gate compares realPaths; an unplaceable spelling is held, not allowed (operator decision after review round 7).
- **No Codex manifest** — mods are Claude Code–only; `.agents/plugins/marketplace.json` is untouched.

## Risks

- Mod API is early access and may shift between Claude Code releases → pin floor in README, keep wiring thin.
- False denies (e.g. editing user-global files inside cwd) → `warn`/`off` switch.
