# Code Review Report: 045-project-custom-presets

**Reviewed:** 2026-10-20
**Model:** claude-sonnet-5-5
**Verdict:** APPROVED_WITH_NOTES

## Summary

3 findings: 0 BLOCK, 2 WARN, 1 NOTE. D8 skipped (design.md absent).

## Findings

### [WARN] plugins/specclaw/bin/specclaw-presets:25 — Correctness
**Problem:** Block-form regex `^presets:[ \t]*\n((?:[ \t]+-[^\n]*\n?)+)` drops the whole list, silently, exit 0, in two valid YAML shapes (reproduced):
`presets:   # chosen` + `  - dotnet`  and  `presets:` + `  # note` + `  - dotnet`. Only `base` prints, so a user's configured preset is quietly ignored. The same silent-drop happens for a comment inside a multi-line flow list (line 22 captures `# x` as a name, giving a spurious unknown, which is at least loud).
**Fix:** allow trailing comment on header: `^presets:[ \t]*(?:#[^\n]*)?\n`, and allow blank/comment lines between items: `((?:[ \t]*(?:#[^\n]*)?\n|[ \t]+-[^\n]*\n?)+)` filtered to lines containing `-`. Add a test for each.

### [WARN] plugins/specclaw/bin/specclaw-presets:32,37 — Security (trust boundary)
**Problem:** `os.path.realpath` follows symlinks, and `os.path.isfile` accepts them. A client repo with `.specclaw/presets/dotnet.md -> /etc/hosts` (reproduced) makes the resolver print `/private/etc/hosts`, which build then reads into the agent context. Names are regex-safe (no `../`), but the file itself is not confined. Preset content is already prompt-injection surface by design; the symlink additionally lets a hostile repo pull arbitrary host files into the model context.
**Fix:** in `local()`, reject when `not os.path.realpath(p).startswith(os.path.realpath(os.path.join(sdir,"presets"))+os.sep)`. Two lines. Document in README that presets are trusted input.

### [NOTE] plugins/specclaw/bin/specclaw-presets:57 — Design/semantics
**Problem:** `Extends:` of an unknown parent warns but still emits the child (rc 1). Matches FR-4/5 loosely; fine, just confirm it is intended. Also `Extends:` is only recognised if it is the first non-blank line (spec-conformant, README says "start the file").

## Checked, no issue
- Path traversal via names: `NAME` regex `^[a-z0-9-]+$` applied in both `builtin` and `local`; `../x` unknown. Good. (`$` permits trailing `\n` in Python `re`, but names come from stripped lines so unreachable.)
- Flow form, quoted names, trailing `# comment`, `presets: []`: correct.
- Extends semantics: self-extend gets built-in, other-name prefers local then built-in, one level, dedupe by path. Matches AC-1..5.
- Scope: init, skills, README, tests, version bumps all match the file map. Full flow untouched.
- Tests cover AC-1..7. AC-6 depends on `$TMP/n` init fixture existing earlier in the script (not verified).

## Verdict Rationale

No BLOCK: spec ACs are met and name-based traversal is closed. Two WARNs: silent loss of configured presets for common YAML comment styles, and symlink escape from the presets dir. Both are small fixes.
