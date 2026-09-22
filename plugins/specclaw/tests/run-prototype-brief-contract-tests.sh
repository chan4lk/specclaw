#!/usr/bin/env bash
# run-prototype-brief-contract-tests.sh — the contract between the brief the
# bf-prototype-architect agent writes and the parser specclaw-bf-prototype
# record reads.
#
# WHY THIS SUITE EXISTS. The agent writes prose and a small block of machine
# directives; bash reads ONLY the directives. That split is what keeps statuses
# computable rather than asserted — but it also means the two halves can drift
# apart silently. A template that renames a directive, or an agent that emits
# five fields where bash reads four, produces no error at all: it produces a
# manifest with screens missing, and a screen missing from the manifest is a
# screen no gate downstream can refuse. The failure mode is an unapproved
# design passing every check.
#
# So this suite runs the REAL parser against a COMPLETE sample brief written
# the way the agent is instructed to write one — every directive type, prose
# around them, a new screen, a retired screen, a provisional one — and asserts
# every directive survived the trip into prototype-manifest.json.
#
# The fixture at tests/fixtures/prototype/prototype-brief.md is deliberately
# realistic rather than minimal. A minimal fixture would pass while the
# document a real agent produces failed.
#
# Bash + coreutils + jq + sha256sum/shasum.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_BIN="$PLUGIN_ROOT/bin/specclaw-bf-prototype"
BRIEF_FIXTURE="$SCRIPT_DIR/fixtures/prototype/prototype-brief.md"
BRIEF_TEMPLATE="$PLUGIN_ROOT/templates/prototype-brief.md"

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
  echo "jq not installed — skipping prototype brief-contract suite (exit 0)."
  exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "no sha256sum/shasum — skipping prototype brief-contract suite (exit 0)."
  exit 0
fi
[ -f "$BRIEF_FIXTURE" ] || { echo "fixture missing: $BRIEF_FIXTURE"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"; SPEC="$REPO/.specclaw"
MANIFEST="$SPEC/prototype/prototype-manifest.json"

mkdir -p "$SPEC/analysis" "$SPEC/ui" "$SPEC/prototype/screens" "$SPEC/prototype/app/src"
printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' \
  > "$SPEC/config.yaml"

# The decision record the fixture brief cites. SQ-006 and SQ-015 are answered
# separately here — the two-citation form — because the fixture's header claims
# exactly that, and a fixture whose header disagrees with its repo would test
# nothing.
cat > "$SPEC/analysis/decisions.md" <<'EOF'
# Decisions

## Decisions

### SQ-006 — UI framework / component library

- **Family:** Standard bank
- **Decision:** Kestrelize
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10

### SQ-013 — UI fidelity policy

- **Family:** Standard bank
- **Decision:** REINTERPRET — new design; the legacy UI is reference material only.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10

### SQ-015 — Target frontend language

- **Family:** Standard bank
- **Decision:** Runescript
- **Decided by:** Priya Raman
- **Date:** 2026-09-12

### CQ-020 — Retire the legacy splash screen?

- **Family:** Extracted
- **Decision:** Yes — it carries no business rule.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-11

### CQ-031 — Add a case dashboard?

- **Family:** Extracted
- **Decision:** Yes — counts link through to a filtered list.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-11
EOF

cat > "$SPEC/analysis/target-architecture.md" <<'EOF'
# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| WinForms shell | Kestrelize | SQ-006 | DECIDED |
EOF

cat > "$SPEC/analysis/pending-questions.md" <<'EOF'
# Pending Questions

### PQ-007 — Should the Draft status be dropped entirely?

- **Status:** OPEN
- **Source:** bf-prototype
- **Trigger:** T7
- **Blocks:** PS-001, SCR-001, DR-023
EOF

cat > "$SPEC/ui/ui-inventory.md" <<'EOF'
# UI Inventory

### SCR-001 — Work order list

Shows DR-021.

### SCR-002 — Customer picker

Shows DR-030.

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

### BL-015 — Customer selection

Acceptance basis cites SCR-002 and DR-030.

### BL-019 — Case dashboard

Acceptance basis cites DR-023. Sanctioned by CQ-031.

### BL-016 — Reports

Acceptance basis cites SCR-003 and DR-040.

## Coverage Check

### UI Screen Coverage (SCR)

- **SCR-001** — Work order list → BL-014
- **SCR-002** — Customer picker → BL-015
- **SCR-003** — Reports → out of scope: BL-016 OUT-OF-SCOPE deferred to phase 2
- **SCR-004** — Splash screen → out of scope: retired by CQ-020
EOF

# THE SAMPLE BRIEF, verbatim. Nothing here rewrites it — if the contract has
# drifted, this is where it shows.
cp "$BRIEF_FIXTURE" "$SPEC/prototype/prototype-brief.md"

printf 'let a = 1\n' > "$SPEC/prototype/app/src/list.rsx"
printf 'let b = 2\n' > "$SPEC/prototype/app/src/util.rs"

echo "== The agent's brief parses into the manifest without loss =="

bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1

[ -f "$MANIFEST" ] || { echo "  FAIL — no manifest was written at all"; exit 1; }

# ── PS: directives ─────────────────────────────────────────────────────────
assert_eq "3" "$(jq -r '[.screens[]] | length' "$MANIFEST")" \
  "every PS: directive became a screen (3 briefed, 3 recorded)"
assert_eq "PS-001 PS-002 PS-003" "$(jq -r '[.screens[].id] | join(" ")' "$MANIFEST")" \
  "…in brief order, with the ids the brief used"
assert_eq "SCR-001" "$(jq -r '.screens[0].replaces[0]' "$MANIFEST")" \
  "the legacy screen a prototype screen replaces survives the parse"
assert_eq "MOD-002" "$(jq -r '.screens[0].module' "$MANIFEST")" "…as does its module"
assert_eq "BL-014" "$(jq -r '.screens[0].backlog_items[0]' "$MANIFEST")" "…its backlog item"
assert_eq "DR-021 DR-022 DR-023" "$(jq -r '.screens[0].rules | join(" ")' "$MANIFEST")" \
  "…and every comma-separated rule, not just the first"

# ── A NEW screen carries no `replaces`, which is what makes it new ─────────
assert_eq "0" "$(jq -r '.screens[] | select(.id=="PS-003") | .replaces | length' "$MANIFEST")" \
  "a NEW screen records no legacy screen, rather than recording the literal NEW"

# ── REVIEW-POINT: directives — the ones the new repo depends on ────────────
assert_eq "5" "$(jq -r '[.screens[].review_points[]] | length' "$MANIFEST")" \
  "every review point survives (5 briefed, 5 recorded)"
assert_eq "2" "$(jq -r '.screens[] | select(.id=="PS-001") | .review_points | length' "$MANIFEST")" \
  "…attached to the right screen"
assert_eq "Order number is visible on load" \
  "$(jq -r '.screens[] | select(.id=="PS-001") | .review_points[0].text' "$MANIFEST")" \
  "…with its text intact"
assert_eq "DR-021" \
  "$(jq -r '.screens[] | select(.id=="PS-001") | .review_points[0].protects' "$MANIFEST")" \
  "…and the rule it protects"
assert_eq "workflow:WO-create:step2" \
  "$(jq -r '.screens[] | select(.id=="PS-002") | .review_points[0].protects' "$MANIFEST")" \
  "a workflow-step reference survives too, colons and all"

# ── PROVISIONAL: and the status it forces ─────────────────────────────────
assert_eq "PQ-007" "$(jq -r '.screens[] | select(.id=="PS-001") | .provisional_ref[0]' "$MANIFEST")" \
  "the provisional reference survives"
assert_eq "PROVISIONAL" "$(jq -r '.screens[] | select(.id=="PS-001") | .status' "$MANIFEST")" \
  "…and an OPEN PQ makes its screen PROVISIONAL"

# ── RETIRED-SCR: honoured, because CQ-020 is decided ──────────────────────
assert_eq "SCR-004" "$(jq -r '.retired_scr[0].id' "$MANIFEST")" "the retired screen survives"
assert_eq "CQ-020" "$(jq -r '.retired_scr[0].decision' "$MANIFEST")" "…citing its decision"

# ── LANG-FILE-CONVENTIONS: enforced as declared, and only as declared ─────
assert_eq "0" "$(jq -r '.language_convention_violations | length' "$MANIFEST")" \
  "a tree matching the brief's declared extensions raises no violation"
printf 'junk\n' > "$SPEC/prototype/app/src/stray.qq"
bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1
assert_eq "src/stray.qq" "$(jq -r '.language_convention_violations[0]' "$MANIFEST")" \
  "…and the SECOND forbidden extension in the list is enforced, not just the first"
rm -f "$SPEC/prototype/app/src/stray.qq"

# ── The stack the brief's header claims is the stack bash resolved ────────
bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1
assert_eq "Kestrelize" "$(jq -r '.stack.framework.value' "$MANIFEST")" \
  "the framework the brief states is the framework bash resolved"
assert_eq "Runescript" "$(jq -r '.stack.language.value' "$MANIFEST")" \
  "…and likewise the language"
assert_eq "SQ-015" "$(jq -r '.stack.language.sanctioned_by' "$MANIFEST")" \
  "…cited to the question the brief cites"

echo
echo "== Prose never reaches the parser =="

# Directive-looking text inside the prose sections must not be picked up: bash
# reads directives by line prefix, so a section that discusses a directive in
# passing must not mint a screen.
cp "$BRIEF_FIXTURE" "$WORK/decoy.md"
{
  printf '\n## A section that talks about directives\n\n'
  printf 'The agent writes a line such as "PS: PS-999 | SCR-999 | MOD-999 | BL-999 | DR-999"\n'
  printf 'when documenting the format, indented or quoted rather than at column zero.\n'
  printf '   PS: PS-998 | SCR-998 | MOD-998 | BL-998 | DR-998\n'
} >> "$WORK/decoy.md"
cp "$WORK/decoy.md" "$SPEC/prototype/prototype-brief.md"
bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1
assert_eq "3" "$(jq -r '[.screens[]] | length' "$MANIFEST")" \
  "a quoted or indented directive in prose does not mint a screen"
cp "$BRIEF_FIXTURE" "$SPEC/prototype/prototype-brief.md"

echo
echo "== The template documents exactly the directives the parser reads =="

# Drift guard in the other direction: every directive keyword the parser greps
# for must appear in the template, and vice versa.
for kind in PS REVIEW-POINT PROVISIONAL RETIRED-SCR LANG-FILE-CONVENTIONS; do
  if grep -q "^    ${kind}: \|^  ${kind}: \|${kind}: <\|${kind}: allow=" "$BRIEF_TEMPLATE"; then
    ok "template documents the ${kind}: directive"
  else
    bad "template documents the ${kind}: directive" "not found in $BRIEF_TEMPLATE"
  fi
  if grep -q "brief_directives \"\$brief\" \"${kind}\"" "$PROTO_BIN"; then
    ok "…and the parser actually reads it"
  else
    bad "…and the parser actually reads it" "no brief_directives call for ${kind}"
  fi
done

echo
echo "prototype brief-contract suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
