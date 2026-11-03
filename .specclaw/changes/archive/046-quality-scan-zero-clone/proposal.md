# Proposal: quality-scan zero-clone join fix

**Created:** 2026-10-29
**Status:** 🟡 Draft

## Problem

`specclaw-bf-quality-collect compare --gate` exits 2 with `gate: not_run` whenever jscpd finds zero clones. In `run_jscpd` (`plugins/specclaw/lib/quality-scan.sh:993`) the join awk uses `NR == FNR` to detect its first file (`$rdir/duplicated`). With zero clones that file is empty, so `NR == FNR` stays true for every row of `$rdir/scanned`; all rows are swallowed as "duplicated" entries, nothing is printed, `$rdir/norm` is empty, and the gate has nothing measured. Hit by change 013-gate-cleanup (T5 blocked) on specclaw 0.8.2. Cleanest codebases fail the gate.

## Proposed Solution

Replace `NR == FNR` with `FILENAME == ARGV[1]` in that awk (correct when file 1 is empty). Add a regression test in `plugins/specclaw/tests/run-quality-scan-tests.sh` with a zero-clone jscpd fixture asserting `norm` lists every scanned file with 0 duplicated lines and the gate produces a verdict.

## Scope

### In Scope
- One-line awk fix at `quality-scan.sh:993`
- Zero-clone regression test in `run-quality-scan-tests.sh`

### Out of Scope
- The `NR == FNR` at line 437 (first file is the pattern list, never empty)
- Plugin version bump / cache refresh

## Impact

- **Size:** bounded (alters an existing flow, one lib file plus its test)
- **Files affected:** 2 (estimated)
- **Complexity:** small
- **Risk:** low

## Open Questions

- None.

---

**To proceed:** Review this proposal and approve to begin planning.
