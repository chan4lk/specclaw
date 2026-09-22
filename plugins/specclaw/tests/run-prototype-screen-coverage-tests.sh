#!/usr/bin/env bash
# run-prototype-screen-coverage-tests.sh — regression suite for how
# /specclaw:bf-prototype `collect` classifies each legacy screen as in-scope,
# out-of-scope or uncovered.
#
# The rule this suite defends: the item→screen join is read from the backlog's
# bash-computed "UI Screen Coverage" section — the canonical, generated record
# of which backlog item renders which screen — NOT only from SCR-### tokens
# inside an item's body. Under a REINTERPRET UI policy the render writes no
# per-item SCR-### citation at all (no visual-fidelity line), so a reader that
# only scanned item bodies saw zero in-scope screens and refused every real
# REINTERPRET project. The out-of-scope half was always read from the section;
# this suite fixes the asymmetry so the in-scope half is too.
#
# Fail-closed properties also defended: a mapping to a missing or non-active
# backlog item never counts as in-scope, and a screen recorded BOTH in scope
# and out of scope is surfaced as a conflict rather than silently resolved.
#
# Tested through `collect`, the public entry point. Bash + coreutils + jq.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_BIN="$PLUGIN_ROOT/bin/specclaw-bf-prototype"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }
assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"
  else bad "$label" "expected [$expected], got [$actual]"; fi
}
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) ok "$label" ;;
    *) bad "$label" "missing [$needle] in: $(printf '%s' "$haystack" | head -3)" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype screen-coverage suite (exit 0)."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Fixture. Fixed REINTERPRET decision record with an invented, unrecognisable
# stack (so nothing here can pass by a resolver "knowing" a framework); only the
# ui-inventory and the backlog vary per case. ───────────────────────────────
DECISIONS='# Decisions

## Decisions

### SQ-006 — UI framework / component library

- **Family:** Standard bank
- **Decision:** Kestrelize (Runescript)
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10

### SQ-013 — UI fidelity policy

- **Family:** Standard bank
- **Decision:** REINTERPRET — new design; the legacy UI is reference material only.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10'

# make_repo <dir> <inventory-body> <backlog-body>
make_repo() {
  local dir="$1" inventory="$2" backlog="$3"
  rm -rf "$dir"
  mkdir -p "$dir/.specclaw/analysis" "$dir/.specclaw/ui"
  printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' \
    > "$dir/.specclaw/config.yaml"
  printf '%s\n' "$DECISIONS" > "$dir/.specclaw/analysis/decisions.md"
  {
    printf '# Target Architecture\n\n## Legacy-to-target mapping\n\n'
    printf '| Legacy element | Target element | Sanctioning decision | Status |\n'
    printf '|---|---|---|---|\n'
    printf '| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |\n'
  } > "$dir/.specclaw/analysis/target-architecture.md"
  printf '%s\n' "$inventory" > "$dir/.specclaw/ui/ui-inventory.md"
  printf '%s\n' "$backlog" > "$dir/.specclaw/analysis/rebuild-backlog.md"
}

collect_json() { bash "$PROTO_BIN" collect "$1/.specclaw" 2>/dev/null; }
scount() { printf '%s' "$1" | jq -r ".screen_counts.$2"; }

echo "== Screen coverage — the in-scope join is read from UI Screen Coverage =="

# ── 1. THE HEADLINE CASE (scenario per the fix): REINTERPRET backlog whose
# items carry NO SCR-### token in their bodies. 10 screens are mapped to active
# items through the UI Screen Coverage section; 5 are recorded out of scope. ──
inv1="# UI Inventory"
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
  inv1="${inv1}

### SCR-0${n} — Screen ${n}

Shows DR-0${n}."
done
bl1="# Rebuild Backlog

## MOD-001 — Core"
for n in 01 02 03 04 05 06 07 08 09 10; do
  bl1="${bl1}

### BL-0${n} — Item ${n}

Acceptance basis: capability ${n}. (Deliberately cites no SCR in the body.)"
done
bl1="${bl1}

## Coverage Check

### UI Screen Coverage (SCR)
"
for n in 01 02 03 04 05 06 07 08 09 10; do
  bl1="${bl1}
- **SCR-0${n}** — Screen ${n} → BL-0${n}"
done
for n in 11 12 13 14 15; do
  bl1="${bl1}
- **SCR-0${n}** — Screen ${n} → out of scope: deferred module — CQ-0${n}"
done
make_repo "$WORK/a" "$inv1" "$bl1"
J="$(collect_json "$WORK/a")"
assert_eq "15" "$(scount "$J" total)"        "REINTERPRET/no-body-SCR: 15 screens total"
assert_eq "10" "$(scount "$J" in_scope)"     "…10 mapped through UI Screen Coverage count as in_scope"
assert_eq "5"  "$(scount "$J" out_of_scope)" "…5 recorded out of scope count as out_of_scope"
assert_eq "0"  "$(scount "$J" uncovered)"    "…and none are left uncovered"

# ── 2. COMPATIBILITY: item-body SCR-### citation still resolves in-scope even
# with no UI Screen Coverage section at all (FAITHFUL/THEME-ONLY and existing
# projects). ────────────────────────────────────────────────────────────────
inv2="# UI Inventory

### SCR-001 — Main list

Shows DR-001."
bl2="# Rebuild Backlog

## MOD-001 — Core

### BL-001 — Main list

Acceptance basis cites SCR-001 and DR-001."
make_repo "$WORK/b" "$inv2" "$bl2"
J="$(collect_json "$WORK/b")"
assert_eq "1" "$(scount "$J" in_scope)"  "item-body SCR citation still counts as in_scope (fallback path)"
assert_eq "0" "$(scount "$J" uncovered)" "…and the screen is not left uncovered"

# ── 3a. FAIL-CLOSED: a coverage mapping to a DEFERRED item is not in-scope. ──
inv3="# UI Inventory

### SCR-001 — List

Shows DR-001.

### SCR-002 — Detail

Shows DR-002."
bl3="# Rebuild Backlog

## MOD-001 — Core

### BL-001 — Active thing

Acceptance basis: no SCR in body.

## Deferred

### BL-090 — DEFERRED — Later thing

Deferred to a later phase.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — List → BL-090
- **SCR-002** — Detail → BL-999"
make_repo "$WORK/c" "$inv3" "$bl3"
J="$(collect_json "$WORK/c")"
assert_eq "0" "$(scount "$J" in_scope)" "mapping to a DEFERRED item (BL-090) does not count as in_scope"
assert_eq "uncovered" "$(printf '%s' "$J" | jq -r '.screens[] | select(.scr=="SCR-001").scope')" \
  "…SCR-001 (mapped only to a deferred item) is uncovered, not in-scope"
assert_eq "uncovered" "$(printf '%s' "$J" | jq -r '.screens[] | select(.scr=="SCR-002").scope')" \
  "…SCR-002 (mapped to a MISSING item BL-999) is uncovered, not in-scope"

# ── 4. FAIL-CLOSED: a screen recorded BOTH in scope and out of scope is a
# conflict — collect stops non-zero rather than silently choosing one. ──────
inv4="# UI Inventory

### SCR-001 — Contested

Shows DR-001."
bl4="# Rebuild Backlog

## MOD-001 — Core

### BL-001 — Active thing

Acceptance basis: no SCR in body.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — Contested → BL-001
- **SCR-001** — Contested → out of scope: also dropped — CQ-060"
make_repo "$WORK/d" "$inv4" "$bl4"
OUT="$(bash "$PROTO_BIN" collect "$WORK/d/.specclaw" 2>&1)"; RC=$?
assert_eq "1" "$RC" "same SCR in scope AND out of scope: collect exits non-zero"
assert_contains "$OUT" "conflict" "…and the message calls it a conflict"
assert_contains "$OUT" "SCR-001" "…and names the offending screen"

# ── 5. DE-DUP: a screen recorded in scope by BOTH the item body AND the
# coverage section counts once, and lists the item once. ────────────────────
inv5="# UI Inventory

### SCR-001 — Doubly recorded

Shows DR-001."
bl5="# Rebuild Backlog

## MOD-001 — Core

### BL-001 — Main

Acceptance basis cites SCR-001 and DR-001.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — Doubly recorded → BL-001"
make_repo "$WORK/e" "$inv5" "$bl5"
J="$(collect_json "$WORK/e")"
assert_eq "1" "$(scount "$J" in_scope)" "a screen recorded in both places counts once"
assert_eq "BL-001" "$(printf '%s' "$J" | jq -r '.screens[] | select(.scr=="SCR-001").backlog_items')" \
  "…and its backlog item is listed once, not duplicated"

echo
echo "prototype screen-coverage suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
