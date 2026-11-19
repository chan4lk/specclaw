# Spec: quality scan survives large repos (jq argument limit)

**Change:** 068-quality-scan-jq-arg-limit
**Created:** 2026-11-19
**Status:** 🟡 Draft

## Overview

`specclaw-quality-scan` passes its three measured tables to `jq` as `--argjson "$(…)"` values. A large repo's
function table exceeds the OS argument limit, so `jq` fails to start (`Argument list too long`, exit 126) and the
gate never reports.

## Approach

One decision: the tables reach `jq` as files (`--slurpfile`), never as arguments. `tsv_json` writes each table's
JSON to the scan's work dir `$W`; the final `jq -n` reads them with `--slurpfile` and unwraps each with `[0]` at
the top of the program, so the rest of the program is unchanged.

File map:
- `plugins/specclaw/bin/specclaw-quality-scan` — the final report step.
- `plugins/specclaw/tests/run-quality-scan-tests.sh` — one new case.

## Requirements

### Functional Requirements

- **FR-1** The function, duplication and clone tables are passed to `jq` by file, not on the command line.
- **FR-2** The JSON report (fields, order of lists, values) and the gate exit codes (0 pass/off, 1 fail, 2 not_run)
  are unchanged for every input the existing tests cover.

### Non-Functional Requirements

- **NFR-1** No new dependency; `jq` `--slurpfile` is available in jq 1.5 and later, as is the rest of the script.

## Acceptance Criteria

1. **AC-1** With a fake lizard that reports more functions than fit in the OS argument limit (a table over
   `getconf ARG_MAX` bytes), `specclaw-quality-scan . --gate` does not exit 126, prints a JSON report whose
   `totals.functions` equals the number of functions reported, and exits by its gate rule.
2. **AC-2** Every existing case in `run-quality-scan-tests.sh` still passes.

## Edge Cases

- Empty tables (no functions, no duplicates, no clones) still give `[]`, `0` totals and the same gate as before.
