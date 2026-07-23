# Spec: Fix infinite-loop OOM in specclaw-verify path extraction

**Change:** verify-glob-oom-fix
**Created:** 2026-07-18
**Status:** 🟡 Draft

## Overview

`specclaw-verify collect` parses `**Files:**` fields in `tasks.md` by repeatedly matching a backtick-quoted token and stripping it off the front of the line. The strip pattern interpolates the captured path unquoted into a `${var#pattern}` prefix removal, so the path is glob-interpreted. A path containing glob metacharacters (`[`, `]`, `?`, `*`) — e.g. a Next.js dynamic route `app/[id]/page.tsx` — makes the strip a no-op; the line never shrinks, the regex re-matches the same token, and the loop grows an array without bound until the process is OOM-killed.

Fix the strip so it always advances regardless of path content, and lock the behavior with a regression test.

## Requirements

### Functional Requirements

- **FR1** — The backtick path-extraction loop in `specclaw-verify` (`collect_change_data`, ~L118–122) MUST terminate for any `**Files:**` line, including paths containing glob metacharacters `[ ] ? *`.
- **FR2** — Extracted paths MUST be the literal text between backticks (e.g. `app/[id]/page.tsx` extracted verbatim), unchanged from current behavior for non-glob paths.
- **FR3** — The comma-separated fallback branch (no-backticks case) in the same function MUST be confirmed free of the same glob-strip defect; fix if present.

### Non-Functional Requirements

- **NFR1** — No new runtime dependencies; plain bash, consistent with existing `specclaw-*` scripts.
- **NFR2** — Existing parser regression suite (`plugins/specclaw/tests/run-parser-tests.sh`) MUST still pass (no regression to B3/B4/NFR2 cases).

## Acceptance Criteria

Each criterion must pass for the change to be considered complete.

- **AC-1** — Given a `tasks.md` with `**Files:** \`app/[id]/page.tsx\``, `specclaw-verify collect` completes within a short timeout (does not hang) and `.changed_files[].path` includes the literal `app/[id]/page.tsx`.
- **AC-2** — Given a `**Files:**` line with multiple backtick paths where one contains `[...slug]`, all paths are extracted exactly once, in order, and the loop terminates.
- **AC-3** — `bash plugins/specclaw/tests/run-parser-tests.sh` exits 0 with the new case(s) reported as PASS and no prior case regressed.
- **AC-4** — For a plain non-glob path (`src/index.ts`), extraction output is byte-identical to pre-fix behavior.

## Edge Cases

- Path with a literal `?` or `*` (glob wildcards) — must extract verbatim, no hang.
- Multiple backtick tokens on one line, mixed glob and non-glob.
- `**Files:**` line with no backticks (comma-separated fallback) — unaffected.
- Empty `**Files:**` field — no paths, loop does not enter.

## Dependencies

None. Self-contained fix in one script plus its test suite.

## Notes

Recommended fix (content-agnostic, glob-safe):
```bash
while [[ "$paths_str" =~ \`([^\`]+)\` ]]; do
  file_paths+=("${BASH_REMATCH[1]}")
  paths_str="${paths_str#*\`}"   # drop up to & incl opening backtick
  paths_str="${paths_str#*\`}"   # drop path + closing backtick
done
```
Broader `${var#unquoted}` audit across all lifecycle scripts is deferred to a follow-up (out of scope), but grep `specclaw-build-context` / `specclaw-gh-sync` checklist builders during build for the same pattern and note findings in learnings.md.
