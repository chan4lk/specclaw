# Proposal: specclaw mod — changes pane, band, status line and propose-gate guard

**Created:** 2026-11-02
**Status:** ✅ Approved

## Problem

specclaw's lifecycle state lives in `.specclaw/changes/*/state.json` and task lists, but inside a Claude Code session it is only visible when someone runs `/specclaw:status` or reads the SessionStart text block, which goes stale the moment a phase moves. The one hard rule — new work must be proposed before any source file is edited — is enforced only by prompt text, so a model that rationalises past it edits code with no change dir and the paper trail is lost for good.

Claude Code mods (https://code.claude.com/docs/en/plugins/mods/overview) run in-process TypeScript hooks that can draw panes and bands, set the status line and intercept tool calls. That gives specclaw a live view and a code-level gate.

## Proposed Solution

A new plugin `plugins/specclaw-mod` containing one mod (`hooks/hooks.json` → `hooks/register.tsx`, plus `types/index.d.ts` for its `$.state`). It reads the project's `.specclaw/` directly through `$.fs`; no new bin scripts.

1. **Changes pane** — `/specclaw-pane` opens a pane beside the chat listing every active (non-archived) change: name, phase, tasks done/total, failed count, verify verdict, PR link when recorded. Task counts come from `tasks.md`, or from `## Tasks` in a lean `change.md`. Refreshes after each tool call that touches `.specclaw/` and on a slow timer.
2. **Band above the prompt** — one line for the *current* change (the most recently updated change not yet at `pr`/archived): `047-specclaw-mod · build · 3/7 tasks`. Hidden when there is no `.specclaw/` or no active change.
3. **Status line entry** — short text: active change count and the change currently in `build`, e.g. `specclaw: 6 active · building 047`.
4. **Propose-gate guard** — a `tool.call` hook on `Edit`, `Write` and `NotebookEdit`. When the target path is inside the repo, outside `.specclaw/`, and no change is in an editable phase (proposal approved, spec/tasks, build), the hook denies the call with a message telling Claude to run `/specclaw:propose` first. Off-switch via plugin `userConfig` (`gate: off | warn | block`, default `block`) so it can be disabled without uninstalling.
5. Registered in `.claude-plugin/marketplace.json` alongside the other plugins, at the shared version.

## Scope

### In Scope
- `plugins/specclaw-mod/` (manifest, hooks module, types contract, `*.test.ts` covering state parsing and the gate decision).
- Marketplace entry + version bump of all plugins (R1).
- Reading both full (`tasks.md`) and lean (`change.md` `## Tasks`) task formats.
- Short README section describing the mod and its gate switch.

### Out of Scope
- Buttons that run lifecycle verbs from the pane (`/specclaw:build` etc.) — follow-up once the read-only view proves useful.
- Writing any specclaw state from the mod; `specclaw-set-phase` stays the only writer.
- Codex / non-Claude-Code hosts (mods are Claude Code–only).
- Replacing the SessionStart hook text or the `using-specclaw` skill.
- Desktop/VS Code–specific layouts beyond what `$.ui.resolve` gives for free.

## Impact

- **Size:** architectural (spike / bounded / architectural) — a new plugin and a new enforcement point other sessions will depend on.
- **Files affected:** ~8 (estimated)
- **Complexity:** medium
- **Risk:** medium — the guard can block legitimate edits if the "editable phase" rule is wrong; mitigated by `warn` mode and the `userConfig` switch.

## Open Questions

- Which phases count as "editable" for the gate? Proposed: any change whose proposal is `approved` and is not yet archived. Is an approved-but-unplanned change enough, or should it require `build` in-progress?
- Should the gate also cover `Bash` commands that write files (`sed -i`, heredocs)? Proposed: no in v1 — too easy to misclassify; document the gap.
- Edits outside `.specclaw/` but not source (e.g. `README.md`, `CLAUDE.md`) — gated too? Proposed: yes, matching the "it's just a doc" red flag.
- Mods need Claude Code ≥ 2.1.287; older clients ignore the plugin silently. Acceptable?

---

**To proceed:** Review this proposal and approve to begin planning.
