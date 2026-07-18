# Tasks: Fix infinite-loop OOM in specclaw-verify path extraction

**Change:** verify-glob-oom-fix
**Created:** 2026-07-18
**Total Tasks:** 3

## Summary

Fix the glob-unsafe backtick strip in `specclaw-verify` so path extraction terminates for dynamic-route paths, add a `timeout`-guarded regression test, and bump the plugin version. Small, low-risk.

## Tasks

### Wave 1 — Fix + test

- [x] `T1` — Make the backtick path-strip glob-safe in `specclaw-verify`
  - Files: `plugins/specclaw/bin/specclaw-verify`
  - Estimate: small
  - Depends:
  - Notes: In `collect_change_data` (~L118–122) replace `paths_str="${paths_str#*\`${BASH_REMATCH[1]}\`}"` with two content-agnostic strips: `paths_str="${paths_str#*\`}"` then `paths_str="${paths_str#*\`}"`. Confirm the comma-separated fallback branch has no `${var#glob}` on captured content (FR3) — leave as-is if clean; note either way.

- [x] `T2` — Add regression test for glob/dynamic-route paths
  - Files: `plugins/specclaw/tests/run-parser-tests.sh`
  - Estimate: small
  - Depends: T1
  - Notes: New case using `make_change` conventions. tasks.md `**Files:**` with `\`app/[id]/page.tsx\`` and a multi-token line containing `\`app/[...slug]/route.ts\``. Run `timeout 10 "$VERIFY" collect ...`, assert exit 0 (no hang) and `.changed_files[].path` contains the literal paths (AC-1, AC-2). Verify full suite still exits 0 (AC-3) and plain-path output unchanged (AC-4).

### Wave 2 — Release

- [x] `T3` — Bump plugin version (patch)
  - Files: `plugins/specclaw/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
  - Estimate: small
  - Depends: T1, T2
  - Notes: Increment patch `X.Y.Z → X.Y.Z+1` in both files, kept in sync. Separate `chore: bump version` commit per project rule.

---

## Legend

- `[ ]` Pending
- `[~]` In Progress
- `[x]` Complete
- `[!]` Failed

**Task format:**
```
- [ ] `T<n>` — <title>
  - Files: <files to create/modify>
  - Estimate: small | medium | large
  - Depends: <task ids> (if any)
  - Notes: <additional context>
```
