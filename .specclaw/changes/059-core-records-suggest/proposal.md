# Proposal: Core records + plugin suggestions at the moment of need

**Created:** 2026-11-14
**Status:** ✅ Approved 2026-11-14
**Feature:** devloop
**Depends on:** none

## Problem

People install core specclaw and nothing else, so most never meet the review loop, fleet or tracker sync.
`/specclaw:verify` skips the review loop **silently** when `specclaw-review` is missing
(`skills/verify/SKILL.md` step 3b). The only hint today is `hooks/session-start`'s `missing()`, which fires
only when a config key is already set — that is, only for people who already know the plugin exists.

Step 1 of folding ION-TBML-SUITE's dev loop (ADR-0017) into specclaw. The planned `specclaw-dash` mod pane
needs one place per change to read lessons from. Timings (`timeline.jsonl`) and review rounds
(`review/round-*.json`) already have one. Lessons do not: they live only as prose in `.specclaw/learnings.md`.

## Proposed Solution

1. **`specclaw-suggest <specclaw_dir> <feature>`** (new `bin/` script, core). Features: `review`, `fleet`,
   `dash`, `sync`, `bf`. It prints one line —
   `Tip: <what it adds>. Install: /plugin install <plugin>@chan4lk (say "no" to never see this again)` —
   only when the plugin is not installed and `<feature>` is not in `.specclaw/config.yaml`
   `plugins.dismissed`. Otherwise it prints nothing. It always exits 0. `--dismiss <feature>` appends to
   that list. The install check moves out of `session-start` into a shared `lib/` helper, which both use.
2. **Call sites** (one line each in the skills):
   - `verify`, when `specclaw-review` is missing → `review`. This replaces the silent skip.
   - `status`, when 2+ approved changes are not yet built → `fleet`.
   - `status` → `dash`.
   - `propose`, when the idea names an issue, work item or PR → `sync`.
   - `init`, on an existing codebase with no `.specclaw/` → `bf`.

   A suggestion is shown once per session per feature. A "no" from the user runs `--dismiss`.
3. **Lessons as records:** `specclaw-log-learning` also appends one
   `{"kind":"lesson","at","category","priority","detail","action"}` line to the change's
   `timeline.jsonl`, the existing append-only sidecar. `learnings.md` is unchanged. No new records file,
   and no second writer.

## Scope

### In Scope
- `bin/specclaw-suggest`, the shared install check in `lib/`, and `session-start` switched to it
- The five skill call sites above, and `plugins.dismissed` in the config template
- The `lesson` line in `timeline.jsonl` from `specclaw-log-learning`
- Tests: suggest (installed, missing, dismissed, unknown feature), the lesson line

### Out of Scope
- Token-per-role capture: the dash pane will scan transcripts the way TBML's `scan.py` does, so it needs no writer
- Lesson recall at plan/build (step 3), guards and size cap (step 2), the `specclaw-dash` plugin itself (steps 4–5)
- Any auto-install. specclaw only prints the command; the user runs it.

## Impact

- **Size:** bounded — it alters existing flows (`session-start`'s `missing()`, verify step 3b, `specclaw-log-learning`) and adds one small script
- **Files affected:** ~9 (1 new bin, 1 lib, session-start, 4 skills, config template, log-learning) plus tests
- **Complexity:** small
- **Risk:** low. Every path exits 0, and a broken suggest prints nothing.

## Open Questions

- Codex: the same scripts run there, but `/plugin install` is Claude Code syntax. Print a Codex install line, or skip suggestions on Codex? Default: print nothing on Codex.

---

**To proceed:** Review this proposal and approve to begin planning.
