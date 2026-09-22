#!/usr/bin/env bash
# run-prototype-id-permanence-tests.sh — PD-06: a PS-### means the same screen
# forever.
#
# WHY IDS MUST NOT MOVE. A PS-### is cited by an approval row a human wrote, by
# a screenshot filename, by the manifest the new repo reads, and by the review
# rows somebody signs months later. If a re-run could renumber them — because a
# screen was added, removed, or reordered in the brief — then every one of those
# citations would silently start pointing at a different screen, and an approval
# recorded against "PS-003" would appear to approve a screen nobody looked at.
# That failure is invisible: nothing errors, the ids all still resolve, and the
# paperwork looks complete.
#
# So the registry is append-only and is the ONLY place an id is minted. This
# suite pins the three ways that could break: re-running with the same screens,
# re-running with a screen removed, and re-running with screens reordered or
# added.
#
# Bash + coreutils + jq.
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
    *) bad "$label" "missing [$needle]" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype id-permanence suite (exit 0)."; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SPEC="$WORK/repo/.specclaw"
mkdir -p "$SPEC/prototype"
REG="$SPEC/prototype/id-registry.json"

alloc() { printf '%s\n' "$@" > "$WORK/keys.txt"; bash "$PROTO_BIN" allocate "$SPEC" "$WORK/keys.txt" 2>/dev/null; }
idof()  { jq -r --arg k "$1" '.[$k] // "MISSING"' "$REG"; }

echo "== First allocation: SCR-mapped ascending, then new screens in brief order =="

# Deliberately supplied out of order, with a new-screen key in the middle, so
# a run that simply numbered them as given would produce a different answer.
OUT="$(alloc "SCR-004" "SCR-001" "CQ-031:new-dashboard" "SCR-002")"
assert_eq "PS-001" "$(idof SCR-001)" "SCR-001 takes the first id"
assert_eq "PS-002" "$(idof SCR-002)" "SCR-002 the second"
assert_eq "PS-003" "$(idof SCR-004)" "SCR-004 the third — ascending by screen, not by input order"
assert_eq "PS-004" "$(idof CQ-031:new-dashboard)" "the new screen is numbered after every SCR-mapped one"
assert_eq "4" "$(jq -r 'length' "$REG")" "four keys registered"

echo
echo "== Re-running changes nothing =="

SNAP="$(jq -S -c . "$REG")"
alloc "SCR-004" "SCR-001" "CQ-031:new-dashboard" "SCR-002" >/dev/null
assert_eq "$SNAP" "$(jq -S -c . "$REG")" "the same key set re-run produces an identical registry"

# Order of the input must not matter either.
alloc "SCR-002" "CQ-031:new-dashboard" "SCR-001" "SCR-004" >/dev/null
assert_eq "$SNAP" "$(jq -S -c . "$REG")" "…and so does the same set supplied in a different order"

echo
echo "== A screen leaving the brief keeps its id; the registry never shrinks =="

# SCR-002 and SCR-004 are dropped from the redesign, and a new screen arrives.
alloc "SCR-001" "CQ-040:audit-log" >/dev/null
# Four keys were registered; this run briefs only one of them and adds one new
# screen, so the registry must hold five — the two dropped screens are still
# there. A registry that tracked only what is currently briefed would hold two.
assert_eq "5" "$(jq -r 'length' "$REG")" "the registry grew and did not shrink"
assert_eq "PS-002" "$(idof SCR-002)" "a dropped screen keeps the id it always had"
assert_eq "PS-003" "$(idof SCR-004)" "…and so does the other one"
assert_eq "PS-001" "$(idof SCR-001)" "a surviving screen is unchanged"

# THE ONE THAT MATTERS: the new screen must not reuse a freed number. If it
# took PS-002, every existing citation of PS-002 would now point at it.
assert_eq "PS-005" "$(idof CQ-040:audit-log)" \
  "a new screen takes the next free id, never a number a dropped screen vacated"

echo
echo "== A dropped screen reports RETIRED rather than vanishing =="

mkdir -p "$SPEC/analysis" "$SPEC/prototype/app/src"
printf 'version: 1\nprototype:\n  skill: "s"\n  output_dir: .specclaw/prototype/app/\n' > "$SPEC/config.yaml"
cat > "$SPEC/analysis/decisions.md" <<'EOF'
# Decisions

## Decisions

### SQ-006 — UI framework / component library

- **Decision:** Kestrelize (Runescript)
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10

### SQ-013 — UI fidelity policy

- **Decision:** REINTERPRET — new design; the legacy UI is reference material only.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10
EOF
cat > "$SPEC/analysis/target-architecture.md" <<'EOF'
# Target Architecture

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |
EOF
cat > "$SPEC/analysis/rebuild-backlog.md" <<'EOF'
# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.
EOF
printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n' > "$WORK/repo/.specclaw/ui-inventory-placeholder.md"
mkdir -p "$SPEC/ui"; printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n' > "$SPEC/ui/ui-inventory.md"
printf '# Prototype brief\n\n## Machine Directives\n\nPS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021\n' > "$SPEC/prototype/prototype-brief.md"
printf 'let a = 1\n' > "$SPEC/prototype/app/src/list.rsx"

bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1
M="$SPEC/prototype/prototype-manifest.json"

assert_eq "PS-001" "$(jq -r '.screens[0].id' "$M")" "the briefed screen is recorded normally"
assert_eq "4" "$(jq -r '.retired_ps | length' "$M")" \
  "every registry id no longer briefed is reported, not dropped"
assert_eq "RETIRED" "$(jq -r '.retired_ps[0].status' "$M")" "…with the RETIRED status"
assert_contains "$(jq -r '[.retired_ps[].id] | join(",")' "$M")" "PS-002" \
  "…naming the ids, so a stale citation can still be traced"

# RETIRED is informational. It must never be able to block readiness, or a
# project could never remove a screen from its redesign.
assert_eq "0" "$(jq -r '[.not_ready_reasons[] | select(test("RETIRED"))] | length' "$M")" \
  "a RETIRED screen contributes no not-ready reason"

echo
echo "== The registry is the only place an id is minted =="

# An id that never came from allocate must not appear from anywhere else.
BEFORE="$(jq -S -c . "$REG")"
bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1
assert_eq "$BEFORE" "$(jq -S -c . "$REG")" "record never mints or alters an id"

OUT="$(printf 'BL-014\n' > "$WORK/bad.txt"; bash "$PROTO_BIN" allocate "$SPEC" "$WORK/bad.txt" 2>&1 || true)"
assert_contains "$OUT" "not a valid allocation key" "a key that is not an SCR or a sanctioning CQ is refused"
assert_eq "$BEFORE" "$(jq -S -c . "$REG")" "…and the refused run changed nothing"

echo
echo "prototype id-permanence suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
