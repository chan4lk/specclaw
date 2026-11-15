# Proposal: specclaw-dash — one mod pane for the build, review and learning loops and token use

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** 059-core-records-suggest

## Problem

The views are split up today:
- Core has `/specclaw-pane`.
- Fleet has `/fleet-pane` and an HTML report.
- ION-TBML-SUITE has its own local token dashboard.

No view shows the review loop or the learnings. There is no single place to sit back and watch a feature
being built.

## Proposed Solution

A new plugin, **`specclaw-dash`**: a Claude Code mod. Its pane `/dash` reads files only; it never writes and
never runs commands. It has five sections, and each one hides behind an "install X" card when its source is
missing:

| Section | Reads |
|---|---|
| Build loop | `.specclaw/changes/*/state.json`, tasks, `timeline.jsonl` spans; fleet jobs from `.specclaw/fleet/report.json` |
| Review loop | `changes/*/review/round-*.json`: rounds, open blockers/majors, escalations, final pass at HEAD |
| Learning loop | `lesson` lines (059), review memory stats (`review_stats`), proposed rules awaiting approval |
| Tokens | Claude Code transcripts under `~/.claude/projects/<this project>`: tokens and API-equivalent cost per session, agent and role, context used. Counts only, never text (port of TBML `scan.py`) |
| Status | band: `dash · <n> building · <n> in review · $<today>`; status-line entry |

## Scope

### In Scope
- `plugins/specclaw-dash/`: plugin manifest, mod (`hooks/mod.json`, `register.tsx`, pure `core/` view
  functions with tests), marketplace entry, README
- The transcript scanner as a pure function over transcript files, tested on fixtures

### Out of Scope
- Any action from the pane: launch, approve, caps (063)
- Replacing `/specclaw-pane` or `/fleet-pane`. They stay; dash links to them.
- Codex: mods do not run there

## Impact

- **Size:** architectural — a new plugin and a view others will extend
- **Files affected:** ~15 (new plugin)
- **Complexity:** large
- **Risk:** low. Read only. A failed read shows a stale or error line and is never shown as live data (TBML D-5).

## Open Questions

- Scanning transcripts on every refresh may be slow on large histories. Scan incrementally by file offset, as TBML does?
- Is the API-equivalent cost wanted on subscription plans, or tokens only?

---

**To proceed:** Review this proposal and approve to begin planning.
