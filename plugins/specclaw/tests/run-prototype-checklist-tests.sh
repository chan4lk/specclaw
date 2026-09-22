#!/usr/bin/env bash
# run-prototype-checklist-tests.sh — PD-12: under REINTERPRET,
# /specclaw:bf-ui --checklist reviews the built screen against the APPROVED
# PROTOTYPE, not against a legacy screenshot.
#
# WHY THIS EXISTS. Before this change, --checklist refused outright under
# REINTERPRET, and correctly: the reference it knows about is a screenshot of
# the legacy application, and reproducing that is exactly what REINTERPRET
# waived. But "no legacy reference" was being treated as "no reference at
# all", and that is wrong — a REINTERPRET project has a better one. A named
# client stakeholder approved each redesigned screen, by name and date, before
# the build started. That approved design is what the built screen should be
# checked against.
#
# THE LOAD-BEARING PROPERTY, and the reason for the odd-looking test below
# that deletes files: the new repo must be able to generate this review from
# the manifest ALONE. prototype-brief.md is never copied across (it is a
# legacy-side working document), and neither is the prototype application. So
# the review points are carried in the manifest, and the suite proves the
# review still generates with the brief and the app absent from disk. If that
# ever stops being true, the copy set silently becomes wrong.
#
# Also asserted: with no manifest, the original refusal is byte-identical —
# a REINTERPRET repo that never ran the prototype stage sees what it always saw.
#
# Bash + coreutils + jq + sha256sum/shasum.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_BIN="$PLUGIN_ROOT/bin/specclaw-bf-prototype"
UI_BIN="$PLUGIN_ROOT/bin/specclaw-bf-ui"

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
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype checklist suite (exit 0)."; exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "no sha256sum/shasum — skipping prototype checklist suite (exit 0)."; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

LEGACY="$WORK/legacy"; NEW="$WORK/new"

build_legacy() {
  rm -rf "$LEGACY"
  mkdir -p "$LEGACY/.specclaw/analysis" "$LEGACY/.specclaw/ui" "$LEGACY/.specclaw/prototype/screens" "$LEGACY/.specclaw/prototype/app/src"
  printf 'version: 1\nprototype:\n  skill: "s"\n  output_dir: .specclaw/prototype/app/\n' > "$LEGACY/.specclaw/config.yaml"
  cat > "$LEGACY/.specclaw/analysis/decisions.md" <<'EOF'
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
  cat > "$LEGACY/.specclaw/analysis/target-architecture.md" <<'EOF'
# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |
EOF
  cat > "$LEGACY/.specclaw/analysis/rebuild-backlog.md" <<'EOF'
# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — Work order list → BL-014
EOF
  printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n' > "$LEGACY/.specclaw/ui/ui-inventory.md"
  cat > "$LEGACY/.specclaw/prototype/prototype-brief.md" <<'EOF'
# Prototype brief

## Machine Directives

PS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021
REVIEW-POINT: PS-001 | DR-021 | Order number is visible on load
REVIEW-POINT: PS-001 | workflow:WO-create:step2 | Customer is selected before the tooth chart is reachable
EOF
  printf 'let a = 1\n' > "$LEGACY/.specclaw/prototype/app/src/list.rsx"
  printf 'shot-001' > "$LEGACY/.specclaw/prototype/screens/PS-001.png"
  bash "$PROTO_BIN" record "$LEGACY/.specclaw" >/dev/null 2>&1
  local h; h="$(jq -r '.generator.tree_hash' "$LEGACY/.specclaw/prototype/prototype-manifest.json")"
  { printf '| Screen | Verdict | Approver | Date | Approved source hash |\n|---|---|---|---|---|\n'
    printf '| PS-001 | APPROVED | Mira Costa | 2026-09-16 | %s |\n' "$h"
  } > "$LEGACY/.specclaw/prototype/prototype-approvals.md"
  bash "$PROTO_BIN" record "$LEGACY/.specclaw" >/dev/null 2>&1
}

# THE COPY SET, exactly as documented: map, manifest, screens/. Nothing else.
build_new() {
  rm -rf "$NEW"; mkdir -p "$NEW/.specclaw/analysis" "$NEW/.specclaw/prototype" "$NEW/.specclaw/changes/003-work-order-list"
  cp "$LEGACY/.specclaw/analysis/decisions.md" "$LEGACY/.specclaw/analysis/rebuild-backlog.md" "$NEW/.specclaw/analysis/"
  cp "$LEGACY/.specclaw/prototype/prototype-manifest.json" "$NEW/.specclaw/prototype/"
  cp -r "$LEGACY/.specclaw/prototype/screens" "$NEW/.specclaw/prototype/"
  printf '# Proposal: Work order list\n\nImplements item BL-014.\n' > "$NEW/.specclaw/changes/003-work-order-list/proposal.md"
}

build_legacy
build_new

echo "== The review generates from the manifest alone =="

# Exactly what the new repo has: no brief, no prototype app, no ui-inventory,
# no design-tokens, no ui-manifest. If any of those were secretly required,
# this call fails and the documented copy set is a lie.
for absent in prototype-brief.md app; do
  if [ -e "$NEW/.specclaw/prototype/$absent" ]; then
    bad "$absent is not copied to the new repo" "it is present"
  else
    ok "$absent is not copied to the new repo"
  fi
done

OUT="$(bash "$UI_BIN" checklist-collect "$NEW/.specclaw" 003-work-order-list 2>&1)"
RC=$?
assert_eq "0" "$RC" "--checklist succeeds under REINTERPRET with an approved prototype"
assert_contains "$OUT" "approved prototype screen" "…and says what it reviewed against"

REVIEW="$NEW/.specclaw/changes/003-work-order-list/ui-review.md"
[ -f "$REVIEW" ] || { echo "  FAIL — no ui-review.md written"; exit 1; }
DOC="$(cat "$REVIEW")"

assert_contains "$DOC" "REINTERPRET (SQ-013)" "the review records the policy it was generated under"
assert_contains "$DOC" "PS-001" "…the approved prototype screen is the reference"
assert_contains "$DOC" "Mira Costa" "…named, with the approver who signed it off"
assert_contains "$DOC" "2026-09-16" "…and the date they signed it"
assert_contains "$DOC" "Order number is visible on load" "each recorded review point becomes a row"
assert_contains "$DOC" "Customer is selected before the tooth chart is reachable" "…all of them, not just the first"
assert_contains "$DOC" "DR-021" "…each naming the rule it protects"
assert_contains "$DOC" "workflow:WO-create:step2" "…including workflow-step references"
assert_contains "$DOC" "Verified by" "…with a column for the human's signature"

# The review is evidence, not a verdict. It must not claim any outcome.
assert_not_contains "$DOC" "PASS" "the review states no pass verdict"
assert_not_contains "$DOC" "MATCH" "…and no match verdict"

# And it must not tell a REINTERPRET reviewer to compare against the legacy UI.
assert_not_contains "$DOC" "legacy screenshot referenced" "…and never asks for a legacy screenshot comparison"

echo
echo "== Rows are only generated against an APPROVED design =="

# Withdraw the approval on the legacy side and re-copy: reviewing against an
# unapproved design would put a human's signature on something nobody agreed to.
printf '| Screen | Verdict | Approver | Date | Approved source hash |\n|---|---|---|---|---|\n| PS-001 | CHANGES-REQUESTED | Mira Costa | 2026-09-17 | deadbeef |\n' \
  > "$LEGACY/.specclaw/prototype/prototype-approvals.md"
bash "$PROTO_BIN" record "$LEGACY/.specclaw" >/dev/null 2>&1
build_new
OUT="$(bash "$UI_BIN" checklist-collect "$NEW/.specclaw" 003-work-order-list 2>&1)"
assert_contains "$OUT" "not approved for BL-014" "an unapproved screen refuses to generate a review"
assert_contains "$OUT" "CHANGES-REQUESTED" "…naming the status it actually has"

echo
echo "== Tampered evidence is reported, never silently accepted =="

build_legacy; build_new
printf 'TAMPERED' > "$NEW/.specclaw/prototype/screens/PS-001.png"
bash "$UI_BIN" checklist-collect "$NEW/.specclaw" 003-work-order-list >/dev/null 2>&1
DOC="$(cat "$REVIEW" 2>/dev/null || true)"
assert_contains "$DOC" "does not match its recorded hash" \
  "a screenshot that changed after approval is flagged in the review itself"

echo
echo "== With no manifest, the original refusal is unchanged =="

build_legacy; build_new
rm -rf "$NEW/.specclaw/prototype"
OUT="$(bash "$UI_BIN" checklist-collect "$NEW/.specclaw" 003-work-order-list 2>&1)"
assert_contains "$OUT" "UI fidelity policy is REINTERPRET (SQ-013) — the legacy UI is reference material only, so no UI fidelity review applies to this or any change. Nothing to generate." \
  "a REINTERPRET repo with no prototype sees the original refusal, verbatim"

echo
echo "prototype checklist suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
