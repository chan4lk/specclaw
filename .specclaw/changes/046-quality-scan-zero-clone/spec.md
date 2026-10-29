# Spec: quality-scan zero-clone join fix

**Change:** 046-quality-scan-zero-clone
**Created:** 2026-10-29
**Status:** 🟡 Draft

## Overview

`run_jscpd` in `plugins/specclaw/lib/quality-scan.sh` joins `$rdir/duplicated` against `$rdir/scanned` with `NR == FNR`. When jscpd reports zero clones `duplicated` is empty, so `NR == FNR` never turns false, every `scanned` row is consumed as a lookup entry, `$rdir/norm` stays empty, and the caller reports `jscpd: parse_error` and `gate: not_run` (exit 2). Reproduced with a fake jscpd emitting `"duplicates":[]` against `bin/specclaw-quality-scan . --gate`.

## Requirements

### Functional Requirements

- FR-1: the join awk identifies its first input by `FILENAME == ARGV[1]`, not `NR == FNR`.
- FR-2: with zero clones, `norm` lists every scanned file with 0 duplicated lines.

### Non-Functional Requirements

- No behaviour change when clones exist. Bash + coreutils only in the suite.

## Acceptance Criteria

- [ ] AC-1: with a jscpd report of `"duplicates":[]` over two scanned files, `specclaw-quality-scan . --gate` reports `tools.jscpd == "ran"`, `totals.lines` equal to the scanned line sum, `totals.duplicated_lines == 0`, `gate == "pass"`, exit 0.
- [ ] AC-2: the existing planted-duplicate case still lists the duplicate and `--gate` still exits 1.
- [ ] AC-3: `run-quality-scan-tests.sh` includes the zero-clone case, fails on the unfixed awk, passes on the fixed one.

## Edge Cases

- Empty `duplicated` AND empty `scanned`: join emits nothing, as before.
- Line 437 (`NR == FNR` over the pattern file) is untouched: its first file is never empty.

## Dependencies

None.

## Notes

## Approach

- Decision: `FILENAME == ARGV[1]` is correct for an empty first file because awk sets `FILENAME` only when it reads the first record of a file. POSIX awk, no gawk-only features.
- File map: `plugins/specclaw/lib/quality-scan.sh` (line ~993), `plugins/specclaw/tests/run-quality-scan-tests.sh`.
