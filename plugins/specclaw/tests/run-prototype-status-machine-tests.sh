#!/usr/bin/env bash
# run-prototype-status-machine-tests.sh — regression suite for PD-10, the
# per-screen status precedence and the whole-prototype readiness line that
# /specclaw:bf-prototype --record computes.
#
# The rule this suite defends: BASH computes every status, the agent only
# narrates it. A status nobody can recompute from the files on disk is a claim,
# not a record, and "the client approved it" is exactly the claim that must
# never rest on an agent's summary.
#
# The precedence order is deliberate and the conflicts are the point:
#
#   1 PROVISIONAL beats a human APPROVED. An undecided behaviour question means
#     nobody has yet agreed to the change the redesign proposes, so the screen
#     cannot be ready no matter who signed it off. THIS is the guard that stops
#     a redesign quietly changing what the system does.
#   2 STALE beats APPROVED. An approval is bound to the exact tree the approver
#     reviewed; edit the prototype afterwards and the approval no longer
#     describes what exists.
#   4 REJECTED is not STALE. A rejected screen whose tree then changed is still
#     rejected — rule 2 cannot fire, because it only reads an APPROVED verdict.
#
# Also covered: a stack decision changed after approval, and the raw
# PROTOTYPE: line plus its exit codes (0 READY / 1 NOT-READY / 2 nothing to
# record), which are what the new repo's gates and a CI step actually read.
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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype status-machine suite (exit 0)."
  exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "no sha256sum/shasum — skipping prototype status-machine suite (exit 0)."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
SPEC="$REPO/.specclaw"
MANIFEST="$SPEC/prototype/prototype-manifest.json"

# ── Fixture: one REINTERPRET repo, two in-scope screens, both briefed. ──────
build_repo() {
  rm -rf "$REPO"
  mkdir -p "$SPEC/analysis" "$SPEC/ui" "$SPEC/prototype/screens" "$SPEC/prototype/app/src"
  printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' \
    > "$SPEC/config.yaml"
  cat > "$SPEC/analysis/decisions.md" <<'EOF'
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

### CQ-020 — Merge the two status columns?

- **Family:** Extracted
- **Decision:** Yes — merge them.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-11
EOF
  cat > "$SPEC/analysis/target-architecture.md" <<'EOF'
# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |
EOF
  cat > "$SPEC/analysis/pending-questions.md" <<'EOF'
# Pending Questions

### PQ-007 — Should the Draft status be dropped entirely?

- **Status:** OPEN
- **Source:** bf-prototype
EOF
  printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n\n### SCR-002 — Customer picker\n\nShows DR-030.\n' \
    > "$SPEC/ui/ui-inventory.md"
  cat > "$SPEC/analysis/rebuild-backlog.md" <<'EOF'
# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.

### BL-015 — Customer selection

Acceptance basis cites SCR-002 and DR-030.
EOF
  cat > "$SPEC/prototype/prototype-brief.md" <<'EOF'
# Prototype brief

## Machine Directives

PS: PS-001 | SCR-001 | MOD-002 | BL-014 | DR-021
PS: PS-002 | SCR-002 | MOD-002 | BL-015 | DR-030
REVIEW-POINT: PS-001 | DR-021 | Order number is visible on load
LANG-FILE-CONVENTIONS: allow=.rs,.rsx forbid=.zz
EOF
  printf 'let a = 1\n' > "$SPEC/prototype/app/src/page.rsx"
}

record()      { bash "$PROTO_BIN" record "$SPEC" 2>/dev/null; }
record_rc()   { bash "$PROTO_BIN" record "$SPEC" >/dev/null 2>&1; echo $?; }
status_of()   { jq -r --arg id "$1" '.screens[] | select(.id == $id) | .status' "$MANIFEST"; }
tree_hash()   { jq -r '.generator.tree_hash' "$MANIFEST"; }
shots()       { printf 'shot-%s' "$1" > "$SPEC/prototype/screens/$1.png"; }

# Write an approvals table. Each argument is "PS-###:VERDICT:HASH".
approvals() {
  { printf '# Prototype approvals\n\n'
    printf '| Screen | Verdict | Approver | Date | Approved source hash |\n'
    printf '|---|---|---|---|---|\n'
    local a
    for a in "$@"; do
      printf '| %s | %s | Mira Costa | 2026-09-16 | %s |\n' \
        "${a%%:*}" "$(printf '%s' "$a" | cut -d: -f2)" "$(printf '%s' "$a" | cut -d: -f3)"
    done
  } > "$SPEC/prototype/prototype-approvals.md"
}

echo "== PD-10 — every status row, in precedence order =="

# ── Row 7: DRAFT. Nothing captured, nothing approved. ──────────────────────
build_repo
record >/dev/null
assert_eq "DRAFT" "$(status_of PS-001)" "row 7 — no screenshot, no approval: DRAFT"

# ── Row 6: IN-REVIEW. A screenshot exists; nobody has signed anything. ────
shots PS-001; shots PS-002
record >/dev/null
assert_eq "IN-REVIEW" "$(status_of PS-001)" "row 6 — screenshot present, no approval row: IN-REVIEW"

# ── Row 5: APPROVED, and the whole prototype READY. ───────────────────────
H="$(tree_hash)"
approvals "PS-001:APPROVED:$H" "PS-002:APPROVED:$H"
OUT="$(record)"
assert_eq "APPROVED" "$(status_of PS-001)" "row 5 — approved at the current tree hash: APPROVED"
assert_eq "PROTOTYPE: READY" "$OUT" "…and the raw line reads exactly PROTOTYPE: READY"
assert_eq "0" "$(record_rc)" "…and the exit code is 0"
assert_eq "true" "$(jq -r '.prototype_ready' "$MANIFEST")" "…and the manifest records prototype_ready: true"

# ── Row 2: STALE. The tree moved after the approval. ──────────────────────
printf 'let b = 2\n' >> "$SPEC/prototype/app/src/page.rsx"
OUT="$(record)"
assert_eq "STALE" "$(status_of PS-001)" "row 2 — approved, then the prototype changed: STALE"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" "…and the prototype is not ready"
assert_eq "1" "$(record_rc)" "…and the exit code is 1"

# ── Row 3: CHANGES-REQUESTED. ─────────────────────────────────────────────
H="$(tree_hash)"
approvals "PS-001:CHANGES-REQUESTED:$H" "PS-002:APPROVED:$H"
record >/dev/null
assert_eq "CHANGES-REQUESTED" "$(status_of PS-001)" "row 3 — verdict CHANGES-REQUESTED"

# ── Row 4: REJECTED. ──────────────────────────────────────────────────────
approvals "PS-001:REJECTED:$H" "PS-002:APPROVED:$H"
record >/dev/null
assert_eq "REJECTED" "$(status_of PS-001)" "row 4 — verdict REJECTED"

echo
echo "== PD-10 — the precedence conflicts, which are the whole point =="

# ── CONFLICT A: APPROVED + an undecided behaviour question -> PROVISIONAL.
# The guard that stops a redesign changing behaviour without a decision. ──
build_repo; shots PS-001; shots PS-002
record >/dev/null; H="$(tree_hash)"
approvals "PS-001:APPROVED:$H" "PS-002:APPROVED:$H"
record >/dev/null
assert_eq "APPROVED" "$(status_of PS-001)" "baseline: PS-001 is APPROVED before the question is raised"
printf 'PROVISIONAL: PS-001 | PQ-007\n' >> "$SPEC/prototype/prototype-brief.md"
OUT="$(record)"
assert_eq "PROVISIONAL" "$(status_of PS-001)" \
  "conflict A — an OPEN PQ outranks a human APPROVED verdict: PROVISIONAL"
assert_eq "APPROVED" "$(status_of PS-002)" "…and an unaffected screen is untouched"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" \
  "…and the prototype cannot reach READY with an undecided behaviour change"

# ── …and the marker clears itself once the question is decided, with the
# screen keeping its id and its approval. That is the PD-07 loop closing. ─
sed -i 's/^PROVISIONAL: PS-001 | PQ-007$/PROVISIONAL: PS-001 | CQ-020/' "$SPEC/prototype/prototype-brief.md"
OUT="$(record)"
assert_eq "APPROVED" "$(status_of PS-001)" \
  "…and once promoted to a DECIDED CQ the marker clears itself"
assert_eq "PROTOTYPE: READY" "$OUT" "…and the prototype is ready again"

# ── CONFLICT B: APPROVED + hash changed -> STALE, not APPROVED. ───────────
build_repo; shots PS-001; shots PS-002
record >/dev/null; H="$(tree_hash)"
approvals "PS-001:APPROVED:$H" "PS-002:APPROVED:$H"
record >/dev/null
printf 'let c = 3\n' >> "$SPEC/prototype/app/src/page.rsx"
record >/dev/null
assert_eq "STALE" "$(status_of PS-001)" "conflict B — APPROVED with a changed tree is STALE"

# ── CONFLICT C: REJECTED + hash changed -> REJECTED, not STALE. Rule 2 only
# reads an APPROVED verdict, so it cannot fire here. ─────────────────────
approvals "PS-001:REJECTED:$H" "PS-002:APPROVED:$H"
record >/dev/null
assert_eq "REJECTED" "$(status_of PS-001)" \
  "conflict C — REJECTED with a changed tree stays REJECTED, never STALE"

# ── CONFLICT D: PROVISIONAL outranks STALE too — rule 1 is first. ─────────
printf 'PROVISIONAL: PS-002 | PQ-007\n' >> "$SPEC/prototype/prototype-brief.md"
record >/dev/null
assert_eq "PROVISIONAL" "$(status_of PS-002)" \
  "conflict D — an OPEN PQ outranks a stale approval as well"

echo
echo "== PD-10 — a stack decision that changed after approval =="

# Approve everything, then change the language decision without touching the
# prototype: every screen still has a valid hash, but the design was approved
# against a stack the project no longer intends to build.
build_repo; shots PS-001; shots PS-002
record >/dev/null; H="$(tree_hash)"
approvals "PS-001:APPROVED:$H" "PS-002:APPROVED:$H"
OUT="$(record)"
assert_eq "PROTOTYPE: READY" "$OUT" "baseline: READY before the stack moves"
sed -i 's/Kestrelize (Runescript)/Kestrelize (Quux)/g' "$SPEC/analysis/decisions.md"
sed -i 's/Kestrelize (Runescript)/Kestrelize (Quux)/g' "$SPEC/analysis/target-architecture.md"
OUT="$(record)"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" "a stack decision changed after approval: NOT-READY"
assert_contains "$OUT" "stack-decision-changed" "…and the reason names the stack, not the screens"

echo
echo "== The raw line and exit codes the gates actually read =="

# ── Exit 2: nothing to record. Distinct from NOT-READY, because "the human
# has not imported the prototype yet" is not "the prototype was rejected". ─
build_repo
rm -f "$SPEC/prototype/app/src/page.rsx"
RC="$(record_rc)"
assert_eq "2" "$RC" "empty prototype.output_dir: exit 2, not 1"
# shellcheck disable=SC2069  # deliberate: `2>&1 >/dev/null` in THIS order sends
# stderr to the original stdout and then discards stdout, which is how these
# assertions capture a command's stderr alone. The refusal messages under test
# are written to stderr; the JSON on stdout would drown them.
OUT="$(bash "$PROTO_BIN" record "$SPEC" 2>&1 >/dev/null)"
assert_contains "$OUT" "prototype.output_dir is empty" "…and says so by name"
assert_contains "$OUT" "Nothing to record" "…and does not call it a failed approval"

# ── A file the brief's declared language conventions forbid. The conventions
# come from the BRIEF, never from a table in the script. ─────────────────
build_repo; shots PS-001; shots PS-002
record >/dev/null; H="$(tree_hash)"
approvals "PS-001:APPROVED:$H" "PS-002:APPROVED:$H"
record >/dev/null
printf 'junk\n' > "$SPEC/prototype/app/src/stray.zz"
OUT="$(record)"
assert_contains "$OUT" "PROTOTYPE: NOT-READY" "a forbidden file extension blocks readiness"
assert_eq "src/stray.zz" "$(jq -r '.language_convention_violations[0]' "$MANIFEST")" \
  "…and the offending file is named in the manifest"

# ── The agent can only narrate what bash printed: every status in the
# manifest is one of the documented values. ──────────────────────────────
BAD="$(jq -r '[.screens[].status] | map(select(. as $s | ["PROVISIONAL","STALE","CHANGES-REQUESTED","REJECTED","APPROVED","IN-REVIEW","DRAFT"] | index($s) | not)) | length' "$MANIFEST")"
assert_eq "0" "$BAD" "every recorded status is one of the seven documented values"

echo
echo "prototype status-machine suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
