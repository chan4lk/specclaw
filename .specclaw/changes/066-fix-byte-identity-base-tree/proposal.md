# Proposal: Fix byte-identity test base tree

**Created:** 2026-11-15
**Status:** 🟡 Draft

## Problem

CI on `main` has been red since #93 (change 042). `plugins/specclaw-bf/tests/run-prototype-byte-identity-tests.sh` extracts the base-ref tree from `plugins/specclaw`, but 042 moved the `specclaw-bf-*` binaries into `plugins/specclaw-bf`. The old binaries are missing (`rc=127`), so 15 of 16 cases fail on every run.

## Proposed Solution

Point `git archive` and `OLD_PLUGIN` at `plugins/specclaw-bf`, so the suite compares the base ref's bf plugin against the working tree's bf plugin.

## Scope

### In Scope
- The two path lines in `run-prototype-byte-identity-tests.sh`.

### Out of Scope
- Any change to the bf binaries themselves.
- The now-redundant `/specclaw:bf-` → `/specclaw-bf:bf-` sed (harmless; left as is).

## Impact

- **Size:** bounded (one-file fix to an existing test)
- **Files affected:** 1
- **Complexity:** small
- **Risk:** low

## Open Questions

None.
