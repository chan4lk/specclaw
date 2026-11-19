# Proposal: quality scan survives large repos (jq argument limit)

**Created:** 2026-11-19
**Status:** 🟡 Draft

## Problem

`specclaw-quality-scan` builds its report by passing the lizard function table, the jscpd duplication table and the
clone list to `jq` as `--argjson "$(…)"` command-line arguments. On a repo with many functions the function table
exceeds the OS argument limit, `jq` cannot start, and the scan dies with `jq: Argument list too long` (exit 126).
`--gate` therefore never reports, and `/specclaw:verify` cannot reach PASS. Seen in fleet run `fleet-042-71919`
on ion-studio (488 tests passing, verify stuck at FAIL).

## Proposed Solution

Write each table's JSON to a file in the scan's work dir and pass it with `--slurpfile`, so no table data goes
on the command line. The report shape, thresholds and gate logic stay exactly as they are.

## Scope

### In Scope
- `plugins/specclaw/bin/specclaw-quality-scan`: tables passed by file, not by argument.
- `plugins/specclaw/tests/run-quality-scan-tests.sh`: one case with a function table larger than the argument
  limit (fake lizard emitting enough rows), asserting the scan exits by its gate, not 126, and lists the totals.

### Out of Scope
- Any change to thresholds, report fields or the gate rule.
- Other scripts that may pass large `--argjson` values (none known to fail).

## Impact

- **Size:** bounded (spike / bounded / architectural) — alters the existing scan's last step only.
- **Files affected:** 2 (estimated)
- **Complexity:** small (small / medium / large)
- **Risk:** low (low / medium / high) — same `jq` program; only how three inputs arrive changes.

## Open Questions

- None. After release, the fleet image (`ghcr.io/chan4lk/specclaw-fleet`) needs a rebuild on the new version so
  fleet verify runs pick up the fix.

---

**To proceed:** Review this proposal and approve to begin planning.
