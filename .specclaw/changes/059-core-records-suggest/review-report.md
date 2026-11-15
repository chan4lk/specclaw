# Code Review Report: 059-core-records-suggest

**Reviewed:** 2026-11-14
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

4 findings: 0 BLOCK, 2 WARN, 2 NOTE

design.md absent (bounded change), skipping D8. D9: all changed files appear in tasks.md `Files:` lists (manifests via T4).

## Findings

### [WARN] plugins/specclaw/bin/specclaw-log-learning:287-293 — Correctness
**Problem:** `json_esc` escapes only `\`, `"`, newline and tab. Other control characters in DETAIL or ACTION (a `\r` from a pasted Windows log, ESC from terminal output) go into the line raw: `s="${s//$'\t'/ }"`. That is invalid JSON. Whatever reads the `lesson` records later (the planned dash pane) would have to skip or choke on the line. The timer is safe because it skips on the `{"kind":"lesson"` prefix and never parses the rest.
**Fix:** Strip the remaining control characters, e.g. `s="$(printf '%s' "$s" | tr '\000-\037' ' ')"`. This replaces the newline and tab lines and covers `\r`.

### [WARN] plugins/specclaw/bin/specclaw-suggest:50-56 — Correctness (config rewrite)
**Problem:** The awk replaces the `  dismissed:` line only. If a user wrote the block-list form (`  dismissed:` followed by `    - review`), `dismissed()` reads an empty list and the rewrite emits `dismissed: [x]` while the `    - review` lines stay behind. The result is invalid YAML in `config.yaml`. The shipped template uses `[]`, so this only hits hand-edited configs. Two smaller points on the same write: `mv` of `"$CONFIG.tmp"` gives the file the umask default mode, not the original mode. The temp name is predictable (`$CONFIG.tmp`), though it sits in the user's own `.specclaw/` dir, so there is no real injection surface.
**Fix:** Say in a comment that only the inline-list form is supported (`shortcut: inline list only, upgrade if block lists appear`). Alternatively, skip the awk and exit 0 when `dismissed:` has an empty value followed by `-` lines. Use `mktemp "$CONFIG.XXXXXX"` if you want an unpredictable temp name.

### [NOTE] plugins/specclaw/bin/specclaw-suggest:44 — Correctness (FR-3)
**Problem:** `feature "$f" >/dev/null || { echo "specclaw-suggest: unknown feature '$f'" >&2; exit 0; }` writes to stderr in `--dismiss` mode. FR-3 only promises silence in suggest mode, so this is within spec. It still exits 0 and is useful. Mentioned for completeness.
**Suggestion:** None needed.

### [NOTE] plugins/specclaw/skills/{verify,status,propose,init}/SKILL.md — Call-site wording
**Problem:** The sentence "show any line it prints, at most once per session; if the user says no, run `--dismiss`" repeats verbatim at every site, and the repeat is acceptable. The status `fleet` condition ("two or more approved changes are not built yet") gives the agent no command to count them. The init condition ("already had code before init") is a judgement call. Both are acceptable for a tip and cannot break anything, since the script exits 0 either way.
**Suggestion:** Optionally point status at the existing `specclaw-parse-tasks`/state data for the count. Otherwise leave it.

## Checked and fine

- **Awk rewrite cases:**
  - A `plugins:` block with a `dismissed:` line replaces it in place.
  - A block without `dismissed:` followed by another top-level key inserts the line before that key.
  - A block at EOF is handled by `END`.
  - No block appends `\nplugins:\n  dismissed: [x]`.
  - `plugin:` (the update-check key) does not match `^plugins:`.
  - `--dismiss` is idempotent through `is_dismissed`.
  - A failed awk removes the tmp file and leaves the config untouched.
- **Exit-0 guarantee:** every path ends in `exit 0`, with no `set -e`. The lib source is guarded with `|| exit 0`, and suggest-mode stderr is silent (`2>/dev/null`).
- **Codex check:** `[ -n "${CODEX_THREAD_ID:-}${CODEX_SANDBOX:-}" ] && exit 0` is correct. It runs after the dismiss branch, so `--dismiss` still works on Codex, which is harmless.
- **session-start:** `PLUGIN_DIR` is defined at line 38 before use. The lib is sourced inside `if . lib 2>/dev/null; then`, so a missing lib skips the notices and cannot abort under `set -euo pipefail`. The router and JSON assembly are untouched. `missing` ends in an assignment, so it returns 0, the same as before. The `installed`/`missing` bodies are moved byte-for-byte.
- **Timer:** the `/^\{"kind":"lesson"/ { next }` rule runs before the unparseable counter. Lesson lines have no `ev` and no `ts`, so elapsed time is unaffected.
- **Versions:** all 6 marketplace entries and all plugin manifests are at 0.9.7, the single bump commit.
- **Scope:** no token capture, no recall, no dash plugin. `run-suggest-tests.sh` passes, and the CI step is added.

## Verdict Rationale

No security issue or data-loss bug. Config writes go through a temp file and a `mv`, the hook cannot drop the router, and every suggest path exits 0. The two WARNs are robustness gaps in edge input (control characters in lesson text, hand-written block-list YAML) and neither affects the normal path. The scope matches the proposal. APPROVED_WITH_NOTES.
