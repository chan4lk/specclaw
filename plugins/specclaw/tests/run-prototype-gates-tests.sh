#!/usr/bin/env bash
# run-prototype-gates-tests.sh — the new-repo gates: nothing production-side
# starts until a named client stakeholder has approved the redesign.
#
# WHAT THESE GATES ARE FOR. Under REINTERPRET the rebuild throws the legacy
# interface away and designs a new one. Somebody has to agree to that new
# design, and the only moment that agreement is cheap is before the
# application exists. Once the new repo is scaffolded and items are being
# built, an approval arriving late is approving something already built.
#
# So both gates FAIL CLOSED, and this suite is mostly about proving that. A
# manifest that is missing, unparseable, not ready, whose screenshots do not
# verify, or which was approved against a different stack, must all stop the
# command — because every one of them means the same thing in practice: there
# is no trustworthy evidence that anybody approved this design. "I could not
# check" is not "it is fine."
#
# Covered here:
#   - bf-bootstrap's eighth precondition, every refusal path, and the pass
#   - the copy-pairing rule: manifest and screens/ travel together or the
#     recorded hashes prove nothing
#   - --adopt refusing a tree that IS the approved prototype (PD-05)
#   - propose's whole-repo and per-item checks (via the verifier they read)
#   - --record's exit 2 on an empty output dir, which means "nothing imported
#     yet", not "the design was rejected"
#
# WHAT THIS SUITE CANNOT TEST, stated rather than implied: /specclaw:propose
# is a SKILL — prose an agent follows — so no bash suite can prove it actually
# stops. What is testable, and tested here, is the mechanical half it reads:
# the verifier's verdict and the exact remedy strings. Same limitation
# run-bootstrap-gate-tests.sh documents for the foundation gate.
#
# Bash + coreutils + jq + sha256sum/shasum.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_BIN="$PLUGIN_ROOT/bin/specclaw-bf-prototype"
BOOT_BIN="$PLUGIN_ROOT/bin/specclaw-bf-bootstrap"

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
    *) bad "$label" "missing [$needle] in: $(printf '%s' "$haystack" | head -2)" ;; esac
}
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype gates suite (exit 0)."; exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "no sha256sum/shasum — skipping prototype gates suite (exit 0)."; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DECISIONS='# Decisions

## Decisions

### SQ-001 — Target platform

- **Decision:** Web application

### SQ-002 — Database engine and hosting

- **Decision:** Managed Postgres

### SQ-003 — Hosting/deployment model

- **Decision:** Containers

### SQ-004 — Authentication/authorization approach

- **Decision:** OIDC

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

### SQ-014 — Target backend stack

- **Decision:** Kestrel API'

ARCH='# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |'

BACKLOG='# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.

### BL-016 — Reports

Acceptance basis cites SCR-003 and DR-040.

### BL-020 — Background job runner

No screen. Acceptance basis cites DR-050.'

# ── A legacy repo taken all the way to PROTOTYPE: READY ────────────────────
build_legacy() {
  local L="$1"
  rm -rf "$L"; mkdir -p "$L/.specclaw/analysis" "$L/.specclaw/ui" "$L/.specclaw/prototype/screens" "$L/.specclaw/prototype/app/src"
  printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' > "$L/.specclaw/config.yaml"
  printf '%s\n' "$DECISIONS" > "$L/.specclaw/analysis/decisions.md"
  printf '%s\n' "$ARCH"      > "$L/.specclaw/analysis/target-architecture.md"
  printf '%s\n' "$BACKLOG"   > "$L/.specclaw/analysis/rebuild-backlog.md"
  printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n\n### SCR-003 — Reports\n\nShows DR-040.\n' > "$L/.specclaw/ui/ui-inventory.md"
  # SCR-003 is scoped out, so only SCR-001 needs an approved screen.
  printf '\n## Coverage Check\n\n### UI Screen Coverage (SCR)\n\n- **SCR-001** — Work order list → BL-014\n- **SCR-003** — Reports → out of scope: BL-016 OUT-OF-SCOPE deferred to phase 2\n' >> "$L/.specclaw/analysis/rebuild-backlog.md"
  printf '# Prototype brief\n\n## Machine Directives\n\nPS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021\nREVIEW-POINT: PS-001 | DR-021 | Order number is visible on load\n' > "$L/.specclaw/prototype/prototype-brief.md"
  printf 'let a = 1\n' > "$L/.specclaw/prototype/app/src/list.rsx"
  printf 'shot' > "$L/.specclaw/prototype/screens/PS-001.png"
  bash "$PROTO_BIN" record "$L/.specclaw" >/dev/null 2>&1
  local h; h="$(jq -r '.generator.tree_hash' "$L/.specclaw/prototype/prototype-manifest.json")"
  { printf '| Screen | Verdict | Approver | Date | Approved source hash |\n|---|---|---|---|---|\n'
    printf '| PS-001 | APPROVED | Mira Costa | 2026-09-16 | %s |\n' "$h"
  } > "$L/.specclaw/prototype/prototype-approvals.md"
  bash "$PROTO_BIN" record "$L/.specclaw" >/dev/null 2>&1
}

# ── The Phase B copy set, plus the three prototype files ───────────────────
build_new_repo() {
  local L="$1" N="$2"
  rm -rf "$N"; mkdir -p "$N/.specclaw/analysis" "$N/.specclaw/prototype"
  cp "$L/.specclaw/analysis/decisions.md" "$L/.specclaw/analysis/rebuild-backlog.md" \
     "$L/.specclaw/analysis/target-architecture.md" "$N/.specclaw/analysis/"
  cp "$L/.specclaw/prototype/prototype-manifest.json" "$N/.specclaw/prototype/"
  cp -r "$L/.specclaw/prototype/screens" "$N/.specclaw/prototype/"
}

LEGACY="$WORK/legacy"
build_legacy "$LEGACY"

echo "== The legacy side reaches READY before anything is copied =="
OUT="$(bash "$PROTO_BIN" record "$LEGACY/.specclaw" 2>/dev/null)"
assert_eq "PROTOTYPE: READY" "$OUT" "the fixture legacy repo records READY"

echo
echo "== bf-bootstrap's eighth precondition =="

NEW="$WORK/new"
build_new_repo "$LEGACY" "$NEW"
# shellcheck disable=SC2069  # deliberate: `2>&1 >/dev/null` in THIS order sends
# stderr to the original stdout and then discards stdout, which is how these
# assertions capture a command's stderr alone. The refusal messages under test
# are written to stderr; the JSON on stdout would drown them.
boot() { bash "$BOOT_BIN" collect "$NEW/.specclaw" 2>&1 >/dev/null; }

OUT="$(bash "$BOOT_BIN" collect "$NEW/.specclaw" 2>/dev/null)"
assert_contains "$OUT" '"mode"' "a READY prototype lets bootstrap proceed to its own collect output"

# Every refusal below must carry the SAME headline remedy, because they are
# all the same situation to the person reading it: go and get it approved.
REMEDY="REINTERPRET project: prototype not approved."

mv "$NEW/.specclaw/prototype/prototype-manifest.json" "$WORK/m.bak"
OUT="$(boot)"
assert_contains "$OUT" "$REMEDY" "manifest absent: refused"
assert_contains "$OUT" "no .specclaw/prototype/prototype-manifest.json" "…naming what is missing"
mv "$WORK/m.bak" "$NEW/.specclaw/prototype/prototype-manifest.json"

cp "$NEW/.specclaw/prototype/prototype-manifest.json" "$WORK/m.bak"
printf 'not json{' > "$NEW/.specclaw/prototype/prototype-manifest.json"
OUT="$(boot)"
assert_contains "$OUT" "$REMEDY" "unparseable manifest: refused, not treated as absent"
assert_contains "$OUT" "it cannot be read, so it proves nothing" "…saying why an unreadable record is not evidence"
cp "$WORK/m.bak" "$NEW/.specclaw/prototype/prototype-manifest.json"

jq '.prototype_ready=false | .not_ready_reasons=["SCR-001 uncovered"]' "$WORK/m.bak" > "$NEW/.specclaw/prototype/prototype-manifest.json"
OUT="$(boot)"
assert_contains "$OUT" "$REMEDY" "prototype_ready false: refused"
assert_contains "$OUT" "SCR-001 uncovered" "…relaying the legacy side's own reason"
cp "$WORK/m.bak" "$NEW/.specclaw/prototype/prototype-manifest.json"

echo
echo "== The copy-pairing rule: the manifest and screens/ travel together =="

mv "$NEW/.specclaw/prototype/screens" "$WORK/sc.bak"
OUT="$(boot)"
assert_contains "$OUT" "always copied together" "manifest without screens/: refused"
mv "$WORK/sc.bak" "$NEW/.specclaw/prototype/screens"

cp "$NEW/.specclaw/prototype/screens/PS-001.png" "$WORK/p.bak"
printf 'TAMPERED' > "$NEW/.specclaw/prototype/screens/PS-001.png"
OUT="$(boot)"
assert_contains "$OUT" "does not match its recorded hash" "a screenshot changed after approval: refused"
cp "$WORK/p.bak" "$NEW/.specclaw/prototype/screens/PS-001.png"

echo
echo "== The stack the design was approved against must still be the stack =="

cp "$NEW/.specclaw/analysis/decisions.md" "$WORK/d.bak"
cp "$NEW/.specclaw/analysis/target-architecture.md" "$WORK/a.bak"
sed -i 's/Kestrelize (Runescript)/Tessera (Runescript)/g' "$NEW/.specclaw/analysis/decisions.md"
sed -i 's/Kestrelize (Runescript)/Tessera (Runescript)/g' "$NEW/.specclaw/analysis/target-architecture.md"
OUT="$(boot)"
assert_contains "$OUT" "stack-decision-changed: framework" "framework changed after approval: refused"
cp "$WORK/d.bak" "$NEW/.specclaw/analysis/decisions.md"; cp "$WORK/a.bak" "$NEW/.specclaw/analysis/target-architecture.md"

sed -i 's/Kestrelize (Runescript)/Kestrelize (Quux)/g' "$NEW/.specclaw/analysis/decisions.md"
sed -i 's/Kestrelize (Runescript)/Kestrelize (Quux)/g' "$NEW/.specclaw/analysis/target-architecture.md"
OUT="$(boot)"
assert_contains "$OUT" "stack-decision-changed" "language changed after approval: refused"
cp "$WORK/d.bak" "$NEW/.specclaw/analysis/decisions.md"; cp "$WORK/a.bak" "$NEW/.specclaw/analysis/target-architecture.md"

OUT="$(bash "$BOOT_BIN" collect "$NEW/.specclaw" 2>/dev/null)"
assert_contains "$OUT" '"mode"' "restored: bootstrap proceeds again"

echo
echo "== PD-05: --adopt refuses the approved prototype itself =="

# The mistake this catches: somebody copies the prototype into the new repo
# and adopts it. It is a runnable app in the right stack, so it looks like a
# foundation — and it is deliberately not one.
AD="$WORK/adopt"
build_new_repo "$LEGACY" "$AD"
cp -r "$LEGACY/.specclaw/prototype/app/." "$AD/"
mkdir -p "$AD/.specclaw/bootstrap"
printf '{"result":"PASS"}' > "$AD/.specclaw/bootstrap/gate-results.json"
printf '{"results":[]}'    > "$AD/.specclaw/bootstrap/smoke-results.json"
printf '# plan\n'          > "$AD/.specclaw/bootstrap/bootstrap-plan.md"
cat > "$AD/.specclaw/bootstrap/.bootstrap-declaration.json" <<'DECL'
{"declaration_schema": 1, "stack": {"name": "Kestrelize"},
 "decisions_consumed": [
   {"id":"SQ-001","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-002","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-003","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-004","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-006","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-013","source":".specclaw/analysis/decisions.md"},
   {"id":"SQ-014","source":".specclaw/analysis/decisions.md"}],
 "pillars": [], "files_created": []}
DECL
OUT="$(bash "$BOOT_BIN" record "$AD/.specclaw" 2>&1)"
assert_contains "$OUT" "This is the approved prototype, not a production foundation. Scaffold fresh." \
  "a tree hashing identically to the prototype is refused by record"
if [ -f "$AD/.specclaw/bootstrap/bootstrap-manifest.json" ]; then
  bad "…and no bootstrap manifest is written" "a manifest was written anyway"
else
  ok "…and no bootstrap manifest is written"
fi

echo
echo "== The propose gates: whole-repo, then per item =="

build_new_repo "$LEGACY" "$NEW"
V="$(bash "$PROTO_BIN" verify "$NEW/.specclaw")"
assert_eq "true" "$(printf '%s' "$V" | jq -r '.ready')" "whole-repo check passes on a READY manifest"

assert_eq "true" "$(bash "$PROTO_BIN" verify "$NEW/.specclaw" --item BL-014 | jq -r '.item_ready')" \
  "an item whose screen is approved passes the per-item check"
assert_eq "true" "$(bash "$PROTO_BIN" verify "$NEW/.specclaw" --item BL-020 | jq -r '.item_ready')" \
  "an item that renders no screen passes on the whole-repo result alone"

# The per-item message has to name the screen AND what is wrong with it —
# "not approved" alone gives nobody anything to act on.
R="$(bash "$PROTO_BIN" verify "$NEW/.specclaw" --item BL-016 | jq -r '.item_reason')"
assert_contains "$R" "Prototype screen(s) not approved for BL-016" "an item citing an uncovered screen is refused"
assert_contains "$R" "SCR-003 → (no prototype screen)" "…naming the screen and that none exists"
assert_contains "$R" "Re-approve, re-record, re-copy" "…and the remedy"

# A STALE screen: the design was signed off, then the prototype changed.
printf 'let b = 2\n' >> "$LEGACY/.specclaw/prototype/app/src/list.rsx"
bash "$PROTO_BIN" record "$LEGACY/.specclaw" >/dev/null 2>&1
build_new_repo "$LEGACY" "$NEW"
V="$(bash "$PROTO_BIN" verify "$NEW/.specclaw")"
assert_eq "false" "$(printf '%s' "$V" | jq -r '.ready')" \
  "a prototype edited after sign-off stops the WHOLE repo, not only its own item"
assert_contains "$(printf '%s' "$V" | jq -r '.reason')" "prototype_ready: false" \
  "…with the reason recorded"

echo
echo "== --record exit codes the gates and CI read =="

EMPTY="$WORK/empty"
build_legacy "$EMPTY"
rm -f "$EMPTY"/.specclaw/prototype/app/src/*
bash "$PROTO_BIN" record "$EMPTY/.specclaw" >/dev/null 2>&1
assert_eq "2" "$?" "empty prototype.output_dir exits 2, distinct from NOT-READY"
# shellcheck disable=SC2069  # deliberate: `2>&1 >/dev/null` in THIS order sends
# stderr to the original stdout and then discards stdout, which is how these
# assertions capture a command's stderr alone. The refusal messages under test
# are written to stderr; the JSON on stdout would drown them.
OUT="$(bash "$PROTO_BIN" record "$EMPTY/.specclaw" 2>&1 >/dev/null)"
assert_contains "$OUT" "prototype.output_dir is empty" "…naming the directory"
assert_not_contains "$OUT" "NOT-READY" "…and never calling it a rejected design"

echo
echo "== Greenfield and non-REINTERPRET repos never see any of this =="

G="$WORK/green"; rm -rf "$G"; mkdir -p "$G/.specclaw/analysis"
assert_eq "false" "$(bash "$PROTO_BIN" verify "$G/.specclaw" | jq -r '.applicable')" \
  "a repo with no rebuild backlog is not applicable"

F="$WORK/faithful"
build_new_repo "$LEGACY" "$F"
sed -i 's/^- \*\*Decision:\*\* REINTERPRET.*$/- **Decision:** FAITHFUL — reproduce the legacy layout exactly./' "$F/.specclaw/analysis/decisions.md"
assert_eq "false" "$(bash "$PROTO_BIN" verify "$F/.specclaw" | jq -r '.applicable')" \
  "a FAITHFUL rebuild is not applicable, even with a manifest sitting there"
# shellcheck disable=SC2069  # deliberate: `2>&1 >/dev/null` in THIS order sends
# stderr to the original stdout and then discards stdout, which is how these
# assertions capture a command's stderr alone. The refusal messages under test
# are written to stderr; the JSON on stdout would drown them.
OUT="$(bash "$BOOT_BIN" collect "$F/.specclaw" 2>&1 >/dev/null)"
assert_not_contains "$OUT" "prototype" "…and bootstrap says nothing about a prototype"

echo
echo "prototype gates suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
