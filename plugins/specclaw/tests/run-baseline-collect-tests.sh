#!/usr/bin/env bash
# run-baseline-collect-tests.sh — regression suite for `specclaw-bf-baseline`'s
# module-map co-ownership reciprocity, in BOTH places it is computed: `collect`
# (module_map.modules[].rules, fed to bf-baseline-designer) and `record`'s
# fallback module derivation (MOD_RULES, used only when a scenario's own
# `Modules:` field is left blank). A `DR-###` rule co-owned by two modules
# must land in BOTH modules' rule sets in either path, even though the
# analyst's convention only requires ONE side to write the annotation.
#
# THE REGRESSION: each rule set used to be computed by grepping a module's OWN
# split-out MOD-###.md text for `DR-###` tokens. A co-owned rule annotated on
# only one module's line (the documented, minimum-required form — see
# agents/bf-domain-analyst.md) never appeared in the OTHER module's own file
# text, so that module's rule set silently omitted it. Downstream,
# bf-baseline-designer derives each scenario's `Modules:` tag from collect's
# index (agents/bf-baseline-designer.md:19,67), so the missing module never
# got tagged onto the fixture and `/specclaw:bf-replay --module` could sign
# that module off clean without ever replaying the rule it implements. The
# fix is one shared pair of functions (coowned_pairs / apply_coowned_rules)
# used by both collect and record, so this suite pins both call sites.
#
# Needs jq (collect's own output is validated through it here).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_BIN="$PLUGIN_ROOT/bin/specclaw-bf-baseline"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }

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
  echo "run-baseline-collect-tests.sh: jq not installed — skipping"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

new_project() { # <root>
  rm -rf "$1"; mkdir -p "$1/.specclaw/analysis"
  printf '# Domain Model\n' > "$1/.specclaw/analysis/domain-model.md"
}

rules_of() { # <collect-json> <mod-id>
  printf '%s' "$1" | jq -r --arg m "$2" '.module_map.modules[] | select(.mod_id == $m) | .rules | sort | join(",")'
}

echo "=================================================="
echo "specclaw-bf-baseline collect — co-ownership reciprocity"
echo "=================================================="

# ── 1. THE REGRESSION: a one-sided annotation still reaches both modules ────
echo
echo "-- reciprocity: annotated on one side only --"

R="$WORK/basic"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001, DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_contains "$(rules_of "$OUT" "MOD-001")" "DR-003" \
  "the annotating module keeps the rule it wrote (grepped from its own file, unaffected by the fix)"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-003" \
  "the named co-owner gets the rule too, though its own section never repeats the id"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "and picks up ONLY the rule it was named on — not MOD-001's other, unrelated rule"

# ── 2. Each annotation pairs with the NEAREST DR-### to its LEFT ────────────
echo
echo "-- pairing: nearest id on the same line, not a leftmost/whole-line match --"

R="$WORK/nearest"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001 (co-owned with MOD-002), DR-002 (co-owned with MOD-003)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None

### MOD-003 — Baz
- **Business rules:** DR-006
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "the first annotation pairs with DR-001, its nearest id, not DR-002"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-002" \
  "and does not also pick up the second rule on the same line"
assert_contains "$(rules_of "$OUT" "MOD-003")" "DR-002" \
  "the second annotation pairs with DR-002, its own nearest id"
assert_not_contains "$(rules_of "$OUT" "MOD-003")" "DR-001" \
  "and does not pick up the first rule on the same line"

# ── 3. A rule already listed on both sides is not duplicated ────────────────
echo
echo "-- no duplicate when both sides already repeat the id --"

R="$WORK/dedup"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-003 (co-owned with MOD-001: dedup check), DR-005
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
MOD2_DR003_COUNT="$(printf '%s' "$OUT" | jq -r '.module_map.modules[] | select(.mod_id == "MOD-002") | [.rules[] | select(. == "DR-003")] | length')"
if [ "$MOD2_DR003_COUNT" = "1" ]; then
  ok "a rule already listed on both sides appears exactly once, not twice"
else
  bad "a rule already listed on both sides appears exactly once, not twice" "got ${MOD2_DR003_COUNT} occurrences"
fi

# ── 4. THE SECOND REGRESSION: record's own fallback derivation ──────────────
#
# A scenario that declares no `Modules:` field at all falls back to `record`
# deriving it from the module map itself (MOD_RULES) — a second, independent
# implementation of the same per-module grep, and the one this suite's
# earlier sections do NOT exercise (they only call `collect`). Fixed by the
# same shared coowned_pairs/apply_coowned_rules pair, so it must show the
# same reciprocity.
echo
echo "-- record's fallback module derivation (no Modules: field declared) --"

R="$WORK/record-fallback"; new_project "$R"
mkdir -p "$R/.specclaw/baseline/fixtures"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Foo
- **Business rules:** DR-001, DR-003 (co-owned with MOD-002: dedup check)
- **Depends on:** None

### MOD-002 — Bar
- **Business rules:** DR-005
- **Depends on:** None
EOF
cat > "$R/.specclaw/baseline/scenarios.md" <<'EOF'
### GM-001 — dedup check, no Modules field declared

- **Seam:** Svc.Do
- **Seam layer:** service
- **Business rules pinned:** DR-003
- **Verifies backlog item:** not yet backlog-linked
EOF
cat > "$R/.specclaw/baseline/fixtures/GM-001.json" <<'EOF'
{"scenario_id":"GM-001","captured_at":"2026-08-07T10:15:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,"result":{"x":1}}}
EOF
bash "$BASELINE_BIN" record "$R/.specclaw" >/dev/null 2>&1
MOD_IDS="$(jq -rc '.fixtures[0].module_ids' "$R/.specclaw/baseline/manifest.json")"
assert_contains "$MOD_IDS" "MOD-001" \
  "the annotating module is still derived (unaffected by the fix)"
assert_contains "$MOD_IDS" "MOD-002" \
  "and the named co-owner is now derived too, though the scenario names no Modules: field at all"

# ── 5. A WITHDRAWN module cannot confer co-ownership (B2) ───────────────────
#
# Co-ownership is a claim a LIVE module makes. A tombstoned module's
# "(co-owned with MOD-###)" is a stale claim about a module that no longer
# exists; honouring it made the named LIVE module accountable for a rule its
# own section never mentions — and it reached manifest.json's module_ids,
# which is what /specclaw:bf-replay --module joins on.
echo
echo "-- a WITHDRAWN module's stale co-ownership claim is not conferred --"

R="$WORK/withdrawn"; new_project "$R"
mkdir -p "$R/.specclaw/baseline/fixtures"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — WITHDRAWN — dead module, merged away
- **Business rules:** DR-900 (co-owned with MOD-002: stale claim)
- **Depends on:** None

### MOD-002 — Live Module
- **Business rules:** DR-010 (co-owned with MOD-003: genuine, still live)
- **Depends on:** None

### MOD-003 — Third
- **Business rules:** DR-020
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-900" \
  "collect: the live module does not inherit a rule claimed by a WITHDRAWN module"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-010" \
  "collect: and keeps its own rule"
assert_contains "$(rules_of "$OUT" "MOD-003")" "DR-020" \
  "collect: a live module's own rule is untouched"
assert_contains "$(rules_of "$OUT" "MOD-003")" "DR-010" \
  "collect: co-ownership between two LIVE modules still works (not over-filtered)"

# Same scenario through record's fallback derivation, which is a second,
# independent computation of the same attribution.
cat > "$R/.specclaw/baseline/scenarios.md" <<'EOF'
### GM-001 — pins only the dead module's rule, declares no Modules field

- **Seam:** Svc.A
- **Seam layer:** service
- **Business rules pinned:** DR-900
- **Verifies backlog item:** not yet backlog-linked
EOF
cat > "$R/.specclaw/baseline/fixtures/GM-001.json" <<'EOF'
{"scenario_id":"GM-001","captured_at":"2026-08-07T10:15:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,"result":{"x":1}}}
EOF
bash "$BASELINE_BIN" record "$R/.specclaw" >/dev/null 2>&1
MIDS="$(jq -rc '.fixtures[0].module_ids' "$R/.specclaw/baseline/manifest.json")"
assert_not_contains "$MIDS" "MOD-002" \
  "record: a withdrawn module's claim does not tag the fixture with the live module"
if [ "$MIDS" = "[]" ]; then
  ok "record: the fixture carries no module at all, since only a tombstone owned its rule"
else
  bad "record: the fixture carries no module at all, since only a tombstone owned its rule" "got ${MIDS}"
fi

# ── 6. Every co-owner on one line is attributed, exactly once (B3) ──────────
#
# The annotation walk used to consume the line as it went, so the text to the
# LEFT of each match was destroyed and a SECOND annotation on the same line had
# no DR-### to pair with — it was dropped in silence. Section 2 above pins the
# other half of this: each annotation still pairs with its own nearest id.
echo
echo "-- two co-owners in one annotation group, and no duplicates --"

R="$WORK/multi-coowner"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Owner
- **Business rules:** DR-020 (co-owned with MOD-002, co-owned with MOD-004)
- **Depends on:** None

### MOD-002 — Second
- **Business rules:** DR-010
- **Depends on:** None

### MOD-004 — Fourth
- **Business rules:** DR-030
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-020" \
  "the first co-owner on the line is attributed"
assert_contains "$(rules_of "$OUT" "MOD-004")" "DR-020" \
  "and so is the second, which used to be dropped in silence"
for M in MOD-002 MOD-004; do
  N="$(printf '%s' "$OUT" | jq -r --arg m "$M" '.module_map.modules[] | select(.mod_id == $m) | [.rules[] | select(. == "DR-020")] | length')"
  if [ "$N" = "1" ]; then
    ok "${M} carries DR-020 exactly once"
  else
    bad "${M} carries DR-020 exactly once" "got ${N} occurrences"
  fi
done

# The same module named twice for one rule is one ownership fact, not two.
R="$WORK/repeated-coowner"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Owner
- **Business rules:** DR-020 (co-owned with MOD-002, co-owned with MOD-002)
- **Depends on:** None

### MOD-002 — Second
- **Business rules:** DR-010
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
N="$(printf '%s' "$OUT" | jq -r '.module_map.modules[] | select(.mod_id == "MOD-002") | [.rules[] | select(. == "DR-020")] | length')"
if [ "$N" = "1" ]; then
  ok "the same module named twice on one line is attributed once, not twice"
else
  bad "the same module named twice on one line is attributed once, not twice" "got ${N}"
fi

# A co-owned annotation with no DR-### to its left still pairs with nothing —
# unchanged behaviour, pinned so the scan-offset rewrite cannot alter it.
R="$WORK/no-dr-left"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Owner
- **Business rules:** (co-owned with MOD-002) DR-001
- **Depends on:** None

### MOD-002 — Second
- **Business rules:** DR-010
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "an annotation with no rule id to its left still attributes nothing"

echo
echo "-- an annotation off the 'Business rules' line confers nothing --"

# The citing module already does not own a DR-### cited in its own "Depends on"
# rationale — that is what scoping the per-module rule grep to the "Business
# rules" line buys. The annotation scan has to agree: a `(co-owned with …)` on
# that SAME sentence used to hand the rule to the named module anyway, so one
# sentence meant "just a citation" for its author and "a real ownership claim"
# for its subject. Both halves are asserted here, because fixing the leak by
# ignoring annotations outright would silently drop the one-sided form the
# analyst charter explicitly permits (agents/bf-domain-analyst.md).
R="$WORK/annotation-off-rules-line"; new_project "$R"
cat > "$R/.specclaw/analysis/module-map.md" <<'EOF'
# Module Map

**Status:** CONFIRMED by H, 2026-08-07

### MOD-001 — Invoicing
- **Business rules:** DR-001, DR-007 (co-owned with MOD-002)
- **Depends on:** None

### MOD-002 — Payments
- **Business rules:** DR-004
- **Depends on:** MOD-001 (needs the invoice balance, DR-001 (co-owned with MOD-003))

### MOD-003 — Customer Accounts
- **Business rules:** DR-006
- **Depends on:** None
EOF
OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"
assert_not_contains "$(rules_of "$OUT" "MOD-003")" "DR-001" \
  "a co-ownership note on a 'Depends on' line confers nothing"
assert_not_contains "$(rules_of "$OUT" "MOD-002")" "DR-001" \
  "and the citing module still does not own the rule it merely cited"
assert_contains "$(rules_of "$OUT" "MOD-002")" "DR-007" \
  "while a note on the 'Business rules' line still confers reciprocally"
assert_contains "$(rules_of "$OUT" "MOD-003")" "DR-006" \
  "and the named module keeps its own declared rule"

echo
echo "-- an absent field reads as empty, never as a failed run --"

# scenario_block_field's grep exits 1 on no match, and under `set -euo pipefail`
# that status used to propagate out of the unguarded command substitutions in
# collect (Seam layer) and record (Seam / Business rules pinned / Verifies
# backlog item), killing the run before it printed anything at all.
#
# Both halves are pinned, because guarding only the tombstone case would fix
# `collect` and leave `record` dying on a live scenario — record already skips
# tombstones before it reads any field.
R="$WORK/absent-field-tombstone"; new_project "$R"
mkdir -p "$R/.specclaw/baseline"
cat > "$R/.specclaw/baseline/scenarios.md" <<'EOF'
## Scenarios

### GM-001 — a live scenario

- **Seam:** Svc.Do
- **Seam layer:** service
- **Business rules pinned:** DR-001
- **Verifies backlog item:** not yet backlog-linked

### GM-008 — WITHDRAWN 2026-09-12, folded into GM-001

_This scenario is no longer designed. Its id stays claimed forever._

## Rule Coverage Check

Nothing to report.
EOF
if OUT="$(bash "$BASELINE_BIN" collect "$R/.specclaw" 2>&1)"; then
  ok "a WITHDRAWN tombstone no longer kills collect (it declares no Seam layer)"
else
  bad "a WITHDRAWN tombstone no longer kills collect (it declares no Seam layer)" \
      "collect exited non-zero; output was [${OUT}]"
fi
assert_contains "$OUT" '"status": "withdrawn"' \
  "and the tombstone is still reported as withdrawn, not skipped silently"
assert_contains "$OUT" '"next_gm_id": "GM-009"' \
  "and its id stays claimed — the next free id counts past it"

# A LIVE scenario missing the same field must still be REFUSED, with the message
# record has always carried for it. That check sits after the field read, so the
# unguarded version was precisely what kept it from ever running: the guard
# restores this error rather than suppressing it.
R="$WORK/absent-field-live"; new_project "$R"
mkdir -p "$R/.specclaw/baseline/fixtures"
cat > "$R/.specclaw/baseline/scenarios.md" <<'EOF'
### GM-001 — a live scenario that declares no seam layer

- **Seam:** Svc.Do
- **Business rules pinned:** DR-001
- **Verifies backlog item:** not yet backlog-linked
EOF
cat > "$R/.specclaw/baseline/fixtures/GM-001.json" <<'EOF'
{"scenario_id":"GM-001","captured_at":"2026-08-07T10:15:00Z","anchor_date":"2026-08-07",
 "legacy_commit_sha":"abc","runtime_version":"1","normalized_fields":[],
 "input":{},"output":{"outcome":"OK","error_code":null,"threw":false,"result":{"x":1}}}
EOF
ERR="$(bash "$BASELINE_BIN" record "$R/.specclaw" 2>&1 >/dev/null || true)"
if [ -f "$R/.specclaw/baseline/manifest.json" ]; then
  bad "a live scenario with no Seam layer is still refused" "a manifest was written anyway"
else
  ok "a live scenario with no Seam layer is still refused"
fi
assert_contains "$ERR" "declares no '- **Seam layer:**' field" \
  "and it says so out loud, instead of dying with no output at all"

echo
echo "=================================================="
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
