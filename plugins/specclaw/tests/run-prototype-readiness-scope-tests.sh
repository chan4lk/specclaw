#!/usr/bin/env bash
# run-prototype-readiness-scope-tests.sh — regression suite for the scope half
# of PD-10: WHICH screens prototype readiness is measured against.
#
# The rule this suite defends: readiness is measured against the REBUILD
# BACKLOG, not against the legacy screen inventory. A rebuild deliberately
# leaves screens behind — a splash screen nobody wants, a report suite scoped
# to a later phase — and a gate that demanded an approved prototype for every
# legacy screen would be unsatisfiable on every real project. It would then be
# switched off, which is worse than not having it.
#
# So exactly three things excuse a legacy screen from blocking:
#   - no active backlog item renders it (it is not in this rebuild at all);
#   - the backlog records it out of scope, with a stated reason;
#   - a DECIDED CQ retired it.
# An UNDECIDED CQ retires nothing — that is the case worth testing, because a
# screen dropped on an unanswered question is precisely the silent scope cut
# this stage exists to surface.
#
# Also covered: RETIRED prototype screens are informational and never block,
# and an item's own SCR citations are what the per-item gate keys on.
#
# Bash + coreutils + jq + sha256sum/shasum.
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
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype readiness-scope suite (exit 0)."
  exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "no sha256sum/shasum — skipping prototype readiness-scope suite (exit 0)."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
SPEC="$REPO/.specclaw"
MANIFEST="$SPEC/prototype/prototype-manifest.json"

# ── Fixture. Four legacy screens with deliberately different fates:
#   SCR-001  rendered by an ACTIVE item          -> must be approved
#   SCR-002  rendered by a STRUCK item only      -> not in the rebuild
#   SCR-003  recorded out of scope by the backlog-> never blocks
#   SCR-004  retired by a CQ (decided or not)    -> depends on the decision
# Only SCR-001 gets a briefed prototype screen. ─────────────────────────────
build_repo() {
  local cq020_decided="$1"
  rm -rf "$REPO"
  mkdir -p "$SPEC/analysis" "$SPEC/ui" "$SPEC/prototype/screens" "$SPEC/prototype/app/src"
  printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' \
    > "$SPEC/config.yaml"
  {
    cat <<'EOF'
# Decisions

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
- **Date:** 2026-09-10
EOF
    if [ "$cq020_decided" = "decided" ]; then
      cat <<'EOF'

### CQ-020 — Retire the legacy splash screen?

- **Family:** Extracted
- **Decision:** Yes — drop it entirely; it carries no business rule.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-11
EOF
    fi
  } > "$SPEC/analysis/decisions.md"
  cat > "$SPEC/analysis/target-architecture.md" <<'EOF'
# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |
EOF
  cat > "$SPEC/ui/ui-inventory.md" <<'EOF'
# UI Inventory

### SCR-001 — Work order list

Shows DR-021.

### SCR-002 — Batch importer

Shows DR-022.

### SCR-003 — Reports

Shows DR-040.

### SCR-004 — Splash screen

Decorative only.
EOF
  cat > "$SPEC/analysis/rebuild-backlog.md" <<'EOF'
# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.

### BL-016 — Reports

Acceptance basis cites SCR-003 and DR-040.

## Struck

### BL-020 — STRUCK — superseded by BL-014, cited SCR-002

Tombstone. Kept so nothing reusing the id points at another item.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — Work order list → BL-014
- **SCR-003** — Reports → out of scope: BL-016 OUT-OF-SCOPE deferred to phase 2
- **SCR-004** — Splash screen → out of scope: dropped from the rebuild
EOF
  cat > "$SPEC/prototype/prototype-brief.md" <<'EOF'
# Prototype brief

## Machine Directives

PS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021
RETIRED-SCR: SCR-004 | CQ-020
EOF
  printf 'let a = 1\n' > "$SPEC/prototype/app/src/page.rsx"
  printf 'shot' > "$SPEC/prototype/screens/PS-001.png"
}

record()    { bash "$PROTO_BIN" record "$SPEC" 2>/dev/null; }
tree_hash() { jq -r '.generator.tree_hash' "$MANIFEST"; }
approve_all() {
  local h="$1"
  { printf '| Screen | Verdict | Approver | Date | Approved source hash |\n'
    printf '|---|---|---|---|---|\n'
    printf '| PS-001 | APPROVED | Mira Costa | 2026-09-16 | %s |\n' "$h"
  } > "$SPEC/prototype/prototype-approvals.md"
}

echo "== Readiness is measured against the rebuild backlog, not the inventory =="

build_repo decided
record >/dev/null
approve_all "$(tree_hash)"
OUT="$(record)"

assert_eq "PROTOTYPE: READY" "$OUT" \
  "one approved screen is enough when every other legacy screen is excused"

assert_not_contains "$(jq -c '.uncovered_scr' "$MANIFEST")" "SCR-002" \
  "a screen only a STRUCK item rendered is not in the rebuild, so it never blocks"
assert_not_contains "$(jq -c '.uncovered_scr' "$MANIFEST")" "SCR-003" \
  "a screen the backlog records out of scope never blocks"
assert_eq "SCR-003" "$(jq -r '.out_of_scope_scr[0].id' "$MANIFEST")" \
  "…and it is LISTED as out of scope, with its reason, rather than silently dropped"
assert_contains "$(jq -r '.out_of_scope_scr[0].backlog_scope' "$MANIFEST")" "deferred to phase 2" \
  "…carrying the backlog's own stated reason"
assert_eq "SCR-004" "$(jq -r '.retired_scr[0].id' "$MANIFEST")" \
  "a screen retired by a DECIDED CQ is recorded as retired"
assert_eq "CQ-020" "$(jq -r '.retired_scr[0].decision' "$MANIFEST")" \
  "…citing the decision that retired it"

echo
echo "== An UNDECIDED question retires nothing =="

# Same repo, same RETIRED-SCR directive — but CQ-020 is not in decisions.md.
# A screen dropped on an unanswered question is a silent scope cut, and the
# record must refuse to call it retired.
build_repo undecided
record >/dev/null
approve_all "$(tree_hash)"
record >/dev/null
assert_eq "0" "$(jq -r '.retired_scr | length' "$MANIFEST")" \
  "an UNDECIDED CQ retires nothing — the retired list stays empty"

echo
echo "== An uncovered in-scope screen DOES block =="

# Put SCR-003 back in scope by making BL-016 an ordinary active item with no
# out-of-scope line, and brief no prototype screen for it.
build_repo decided
sed -i '/SCR-003.*out of scope/d' "$SPEC/analysis/rebuild-backlog.md"
record >/dev/null
approve_all "$(tree_hash)"
OUT="$(record)"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" "an in-scope screen with no approved prototype blocks"
assert_contains "$OUT" "SCR-003 uncovered" "…and the raw line names the exact screen"
assert_eq "SCR-003" "$(jq -r '.uncovered_scr[0]' "$MANIFEST")" "…and the manifest lists it as uncovered"
assert_contains "$(jq -r '.not_ready_reasons | join(", ")' "$MANIFEST")" "SCR-003" \
  "…and the reason is recorded, not just printed"

echo
echo "== A covering screen that is not APPROVED blocks even when one exists =="

build_repo decided
printf 'PS: PS-002 | SCR-003 | MOD-002 | BL-016 | DR-040\n' >> "$SPEC/prototype/prototype-brief.md"
sed -i '/SCR-003.*out of scope/d' "$SPEC/analysis/rebuild-backlog.md"
record >/dev/null
approve_all "$(tree_hash)"   # PS-001 only; PS-002 is left unapproved
OUT="$(record)"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" "a briefed but unapproved screen still blocks"
assert_eq "SCR-003" "$(jq -r '.uncovered_scr[0]' "$MANIFEST")" \
  "…and the screen it fails to cover is named"
assert_eq "DRAFT" "$(jq -r '.screens[] | select(.id=="PS-002") | .status' "$MANIFEST")" \
  "…and the unapproved screen is visible in its own right"

echo
echo "== RETIRED prototype screens are informational and never block =="

# Allocate ids for two screens, then brief only one. The other keeps its id
# forever and reports RETIRED rather than freeing the number.
build_repo decided
printf 'SCR-001\nSCR-002\n' > "$WORK/keys.txt"
bash "$PROTO_BIN" allocate "$SPEC" "$WORK/keys.txt" >/dev/null 2>&1
record >/dev/null
approve_all "$(tree_hash)"
OUT="$(record)"
assert_eq "PROTOTYPE: READY" "$OUT" "a RETIRED prototype screen does not block readiness"
assert_eq "PS-002" "$(jq -r '.retired_ps[0].id' "$MANIFEST")" \
  "…and it is reported as RETIRED, keeping its id"
assert_eq "RETIRED" "$(jq -r '.retired_ps[0].status' "$MANIFEST")" "…with the RETIRED status"

echo
echo "== The per-item gate keys on the item's own SCR citations =="

build_repo decided
record >/dev/null
approve_all "$(tree_hash)"
record >/dev/null
assert_eq "true" "$(bash "$PROTO_BIN" verify "$SPEC" --item BL-014 | jq -r '.item_ready')" \
  "an item whose screens are approved passes"
assert_eq "false" "$(bash "$PROTO_BIN" verify "$SPEC" --item BL-016 | jq -r '.item_ready')" \
  "an item citing a screen with no approved prototype is refused"
assert_contains "$(bash "$PROTO_BIN" verify "$SPEC" --item BL-016 | jq -r '.item_reason')" \
  "SCR-003 → (no prototype screen)" "…naming the screen and what is missing"
assert_contains "$(bash "$PROTO_BIN" verify "$SPEC" --item BL-016 | jq -r '.item_reason')" \
  "Re-approve, re-record, re-copy" "…and the remedy"

echo
echo "prototype readiness-scope suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
