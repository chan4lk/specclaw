#!/usr/bin/env bash
# run-party-tests.sh — regression suite for `bin/specclaw-party` (change 032-party-mode).
#
# Covers the arithmetic half of party mode — the half a model must never decide:
# seat resolution (AC1-AC3, AC5, AC6), the fail-loud fallback (AC4), the
# override/cache paths (AC7, AC8), the block-scoped config reader (AC15), the
# verdict tally (AC9, AC10) and the report grammar the existing parsers read
# (AC11, AC12), plus Edge Cases 1-7, 9 and 10.
#
# The regression this suite exists to pin (AC15 / FR17):
#   the shared yaml_val (specclaw-loop:87-102) reduces a dotted path `a.b.c` to
#   its last component `c:` and greps the WHOLE file for the first hit.
#   config.yaml already carries a top-level `models:` block (planning/coding/
#   review), so `yaml_val party.models` silently returns that block instead of
#   the party one — every panelist would then be spawned on the planning model
#   and `party.models` would be dead config that looks live. `party_val` is
#   block-scoped (the `da_val` precedent, specclaw-build:557-574). The fixture
#   config carries decoy keys in the blocks *above* `party:` (see mkfixture), so
#   the AC15 case below goes red the moment anyone swaps party_val back for the
#   shared helper — rather than passing by luck because no key names collide.
#
# NFR4 — no model spawn, no network: the classifier is stubbed by pre-writing
# changes/<change>/party/classification.json, which is exactly what the handshake
# (exit 10) asks a caller to produce.
# NFR3 — no jq: python3 reads JSON, as in tests/run-synth-agent-tests.sh:44.
#
# Plain bash + coreutils + python3. Run from anywhere:
#   bash plugins/specclaw/tests/run-party-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
PARTY="$BIN_DIR/specclaw-party"

[[ -x "$PARTY" ]] || { echo "FATAL: missing or non-executable: $PARTY" >&2; exit 2; }
command -v python3 >/dev/null || { echo "FATAL: python3 required" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label — expected '$expected', got '$actual'"
  fi
}

# assert_grep <label> <pattern> <file>
assert_grep() {
  if grep -qE "$2" "$3"; then pass "$1"; else fail "$1 — no match for '$2' in $3"; fi
}

# assert_no_grep <label> <pattern> <file>
assert_no_grep() {
  if grep -qE "$2" "$3"; then fail "$1 — unexpected match for '$2' in $3"; else pass "$1"; fi
}

# jget <python-expr on `d`> — read JSON from stdin (run-synth-agent-tests.sh:44)
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

CHANGE="party-fixture"
OUT="$WORK/out"      # last stdout
ERR="$WORK/err"      # last stderr
RC=0                 # last exit code

# ── Fixture builders ──────────────────────────────────────────────────────────

# mkfixture <dir> [key=value ...]
#
# Builds a self-contained .specclaw tree: a non-empty proposal.md, the five
# panelist charters, and a config.yaml shaped like the real template — a
# top-level `models:` block AND a `party:` block with its own `models:`. The
# charters carry a sentinel `model:` so a test can tell "resolved from
# party.models" apart from "fell through to the charter frontmatter".
#
# Recognised keys: panel_mode, panel, always, always_block, min_seats,
# max_seats, rounds, block.
mkfixture() {
  local dir="$1"; shift
  local panel_mode="dynamic" panel="[party-po, party-architect, party-ba, party-visionary]"
  local always="[]" always_block="" min_seats="2" max_seats="6" rounds="2" block="false"
  local kv
  for kv in "$@"; do
    case "$kv" in
      panel_mode=*)   panel_mode="${kv#*=}" ;;
      panel=*)        panel="${kv#*=}" ;;
      always=*)       always="${kv#*=}" ;;
      always_block=*) always_block="${kv#*=}" ;;
      min_seats=*)    min_seats="${kv#*=}" ;;
      max_seats=*)    max_seats="${kv#*=}" ;;
      rounds=*)       rounds="${kv#*=}" ;;
      block=*)        block="${kv#*=}" ;;
      *) echo "FATAL: mkfixture got an unknown key: $kv" >&2; exit 2 ;;
    esac
  done

  mkdir -p "$dir/changes/$CHANGE" "$dir/agents"
  cat > "$dir/changes/$CHANGE/proposal.md" <<'EOF'
# Proposal: a fixture proposal

**Complexity:** low
**Risk:** low

## Problem

Something is wrong.

## Proposed Solution

Fix it.
EOF

  local seat
  for seat in party-po party-architect party-ba party-visionary party-security; do
    cat > "$dir/agents/$seat.md" <<EOF
---
name: $seat
description: fixture charter for $seat
tools: Read
model: charter-${seat#party-}
---

Fixture charter. Attacks one dimension; comments on nothing else.
EOF
  done

  {
    printf 'version: 1\n\n'
    # The top-level block AC15 says must not leak into party.models. The first
    # three keys are the shipped ones; the two party-* keys under them are
    # decoys, and they are the point of this fixture. A whole-file reader
    # reduces `party.models.party-visionary` to `party-visionary:` and takes the
    # FIRST hit in the file — the decoy. Without them a broken reader finds the
    # party block's copy by luck and AC15 passes while FR17 is violated.
    printf 'models:\n'
    printf '  planning: "anthropic/claude-opus-4-8"\n'
    printf '  coding: "anthropic/claude-sonnet-5"\n'
    printf '  review: "anthropic/claude-sonnet-5"\n'
    printf '  party-visionary: DECOY-top-level-models\n'
    printf '  party-po: DECOY-top-level-models\n\n'
    # The same trap for every scalar and list key `panel` and `tally` read, in a
    # block that sits before `party:`. The collision is real in the shipped
    # config — `loop.enabled` and `party.enabled` — so a regression from the
    # block-scoped party_val back to the shared yaml_val turns most cases in
    # this file red instead of quietly reading the wrong block.
    printf 'decoy:\n'
    printf '  rounds: 99\n'
    printf '  block: true\n'
    printf '  panel_mode: fixed\n'
    printf '  panel: [decoy-seat]\n'
    printf '  always: [decoy-seat]\n'
    printf '  min_seats: 9\n'
    printf '  max_seats: 9\n\n'
    printf 'workflow:\n  code_review: true\n\n'
    printf 'party:\n'
    printf '  enabled: true\n'
    printf '  default: false\n'
    printf '  rounds: %s\n' "$rounds"
    printf '  block: %s\n' "$block"
    printf '  panel_mode: %s\n' "$panel_mode"
    printf '  panel: %s\n' "$panel"
    if [[ -n "$always_block" ]]; then
      printf '  always:\n'
      local a items=()
      read -r -a items <<< "$always_block"
      for a in "${items[@]}"; do printf '    - %s\n' "$a"; done
    else
      printf '  always: %s\n' "$always"
    fi
    printf '  min_seats: %s\n' "$min_seats"
    printf '  max_seats: %s\n' "$max_seats"
    printf '  models:\n'
    printf '    party-classifier: haiku\n'
    printf '    party-visionary: fable\n'
    printf '    party-architect: opus\n'
    printf '    party-security: opus\n'
    printf '    party-ba: sonnet\n'
    printf '    party-po: sonnet\n'
  } > "$dir/config.yaml"
}

# stub_classifier <dir> — the classifier's answer, read from stdin. This is the
# whole model-substitute: `panel` only ever reads this file.
stub_classifier() {
  mkdir -p "$1/changes/$CHANGE/party"
  cat > "$1/changes/$CHANGE/party/classification.json"
}

# runp <dir> [panel args...] → stdout in $OUT, stderr in $ERR, status in $RC
runp() {
  local dir="$1"; shift
  "$PARTY" panel "$dir" "$CHANGE" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}

# runt <dir> [tally args...]
runt() {
  local dir="$1"; shift
  "$PARTY" tally "$dir" "$CHANGE" "$@" >"$OUT" 2>"$ERR"
  RC=$?
}

# runr <dir> — report; the produced file is $dir/changes/$CHANGE/party-report.md
runr() {
  "$PARTY" report "$1" "$CHANGE" >"$OUT" 2>"$ERR"
  RC=$?
}

seats_of()   { jget "','.join(s['role'] for s in d['seats'])" < "$OUT"; }
models_of()  { jget "dict((s['role'], s['model']) for s in d['seats'])['$1']" < "$OUT"; }
dropped_of() { jget "','.join(x['role'] + ':' + x['reason'] for x in d['dropped'])" < "$OUT"; }
field_of()   { jget "d['$1']" < "$OUT"; }
count_of()   { jget "len(d['seats'])" < "$OUT"; }

# add_finding <dir> <round> <role> <sev> <status> <title>
add_finding() {
  local dir="$1" round="$2" role="$3" sev="$4" status="$5" title="$6"
  local fdir="$dir/changes/$CHANGE/party/findings-r$round"
  mkdir -p "$fdir"
  {
    printf '### [%s] %s — %s\n' "$sev" "$role" "$title"
    printf '**Quotes:** > **Complexity:** low\n'
    printf '**Problem:** %s\n' "$title"
    printf '**Fix:** rewrite the section.\n'
    printf '**Status:** %s\n\n' "$status"
  } >> "$fdir/$role.md"
}

echo "=== specclaw-party: seats, fallback, cache, tally, report ==="
echo "bin: $PARTY"
echo

# ── AC1 — thin draws exactly two seats ────────────────────────────────────────
echo "--- AC1: {\"tier\":\"thin\"} → [party-po, party-architect], tier_source classifier ---"
D="$WORK/ac1"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "One file, reversible.", "domains": []}
EOF
runp "$D" --json
assert_eq "AC1 exit 0" "0" "$RC"
assert_eq "AC1 seats" "party-po,party-architect" "$(seats_of)"
assert_eq "AC1 tier" "thin" "$(field_of tier)"
assert_eq "AC1 tier_source" "classifier" "$(field_of tier_source)"
assert_eq "AC1 rationale round-trips" "One file, reversible." "$(field_of rationale)"
echo

# ── AC2 — deep seats Security with no domain flag ─────────────────────────────
echo "--- AC2: {\"tier\":\"deep\"} seats Security without any domain flag ---"
D="$WORK/ac2"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Four subsystems, irreversible."}
EOF
runp "$D" --json
assert_eq "AC2 exit 0" "0" "$RC"
assert_eq "AC2 seats (Security seated by depth alone)" \
  "party-po,party-architect,party-ba,party-visionary,party-security" "$(seats_of)"
assert_eq "AC2 domains stayed empty" "" "$(jget "','.join(d['domains'])" < "$OUT")"
echo

# ── AC3 — a domain flag seats the specialist independently of tier ────────────
echo "--- AC3: {\"tier\":\"thin\",\"domains\":[\"security\"]} → three seats ---"
D="$WORK/ac3"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": ["security"], "rationale": "Small, but touches the token path."}
EOF
runp "$D" --json
assert_eq "AC3 exit 0" "0" "$RC"
assert_eq "AC3 seats" "party-po,party-architect,party-security" "$(seats_of)"
assert_eq "AC3 domains recorded" "security" "$(jget "','.join(d['domains'])" < "$OUT")"
echo

# ── AC4 — fail loud, never quiet; never `thin` ────────────────────────────────
# Three distinct failures, one shared contract: tier standard, tier_source
# fallback, a stderr warning, exit 0.
echo "--- AC4a: no classifier answer at all (the handshake, then the fallback) ---"
D="$WORK/ac4a"; mkfixture "$D"
runp "$D" --json
assert_eq "AC4a first run asks for a classifier turn (exit 10)" "10" "$RC"
assert_grep "AC4a request names the target path" "^target: .*/party/classification\.json$" "$OUT"
# The caller never wrote the answer. The second run must not hang or re-ask.
runp "$D" --json
assert_eq "AC4a exit 0 on the fallback" "0" "$RC"
assert_eq "AC4a tier" "standard" "$(field_of tier)"
assert_eq "AC4a tier_source" "fallback" "$(field_of tier_source)"
assert_grep "AC4a warns on stderr" "^WARN: " "$ERR"

echo "--- AC4b: unparseable garbage ---"
D="$WORK/ac4b"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
I could not decide. <<< not json at all {{{
EOF
runp "$D" --json
assert_eq "AC4b exit 0" "0" "$RC"
assert_eq "AC4b tier" "standard" "$(field_of tier)"
assert_eq "AC4b tier_source" "fallback" "$(field_of tier_source)"
assert_grep "AC4b warns on stderr" "^WARN: .*falling back to tier standard" "$ERR"

echo "--- AC4c: valid JSON, unknown tier ---"
D="$WORK/ac4c"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "enormous", "rationale": "Bigger than deep."}
EOF
runp "$D" --json
assert_eq "AC4c exit 0" "0" "$RC"
assert_eq "AC4c tier" "standard" "$(field_of tier)"
assert_eq "AC4c tier_source" "fallback" "$(field_of tier_source)"
assert_grep "AC4c names the unusable tier" "enormous" "$ERR"
# The invariant behind all three: a broken classifier must never SHRINK the panel.
assert_eq "AC4 fallback is never thin (3 seats, not 2)" "3" "$(count_of)"
echo

# ── Edge Case 2 — JSON arrives fenced or wrapped in prose ─────────────────────
echo "--- EC2: tier parsed out of a fenced block and out of prose ---"
D="$WORK/ec2a"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
Here is my classification.

```json
{"tier": "deep", "domains": ["security"], "rationale": "Touches the trust boundary."}
```

That is my answer.
EOF
runp "$D" --json
assert_eq "EC2 fenced JSON classifies (not the fallback)" "classifier" "$(field_of tier_source)"
assert_eq "EC2 fenced JSON tier" "deep" "$(field_of tier)"

D="$WORK/ec2b"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
After reading the artifact I judge it as follows: {"tier":"thin","rationale":"One script."} — done.
EOF
runp "$D" --json
assert_eq "EC2 prose-wrapped JSON tier" "thin" "$(field_of tier)"
assert_eq "EC2 prose-wrapped JSON tier_source" "classifier" "$(field_of tier_source)"
echo

# ── AC5 — max_seats clamps from the tail ──────────────────────────────────────
echo "--- AC5: max_seats: 3 on deep drops from the tail and records why ---"
D="$WORK/ac5"; mkfixture "$D" max_seats=3
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Five subsystems."}
EOF
runp "$D" --json
assert_eq "AC5 exit 0" "0" "$RC"
assert_eq "AC5 three seats survive" "3" "$(count_of)"
assert_eq "AC5 the survivors are the head of the tier order" \
  "party-po,party-architect,party-ba" "$(seats_of)"
# Tail-first: Security then Visionary go before Architect is ever considered.
assert_eq "AC5 dropped names the seats and the reason" \
  "party-security:max_seats,party-visionary:max_seats" "$(dropped_of)"
echo

# ── AC6 — min_seats is never violated; party.always seats a specialist ────────
echo "--- AC6: min_seats grows a short panel along the tier order ---"
D="$WORK/ac6a"; mkfixture "$D" min_seats=3
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "AC6 min_seats: 3 on a thin (2-seat) tier yields 3" "3" "$(count_of)"
assert_eq "AC6 the grown seat comes from the tier order" \
  "party-po,party-architect,party-ba" "$(seats_of)"

echo "--- AC6: party.always seats Security at thin — inline [a, b] list form ---"
D="$WORK/ac6b"; mkfixture "$D" always="[party-security]"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "AC6 inline always seats Security at thin" \
  "party-po,party-architect,party-security" "$(seats_of)"

echo "--- AC6: same, block '- a' list form (both shapes appear in the wild) ---"
D="$WORK/ac6c"; mkfixture "$D" always_block="party-security"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "AC6 block-form always seats Security at thin" \
  "party-po,party-architect,party-security" "$(seats_of)"
echo

# ── AC7 — overrides bypass the classifier entirely ────────────────────────────
# Proof, not assumption: classification.json says something *different*, and the
# `.classifier-requested` marker (the only trace a classifier turn leaves) must
# not appear. Were the classifier consulted, an absent answer would exit 10.
echo "--- AC7: --panel deep ignores classification.json ---"
D="$WORK/ac7a"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "The classifier said thin and must be ignored."}
EOF
runp "$D" --panel deep --json
assert_eq "AC7 --panel exit 0" "0" "$RC"
assert_eq "AC7 --panel tier wins over the stub" "deep" "$(field_of tier)"
assert_eq "AC7 --panel tier_source" "override" "$(field_of tier_source)"
assert_eq "AC7 --panel roster is the deep roster" \
  "party-po,party-architect,party-ba,party-visionary,party-security" "$(seats_of)"
assert_no_grep "AC7 --panel did not adopt the stub's rationale" "must be ignored" "$OUT"
if [[ -e "$D/changes/$CHANGE/party/.classifier-requested" ]]; then
  fail "AC7 --panel left a classifier-request marker"
else
  pass "AC7 --panel requested no classifier turn"
fi

echo "--- AC7: panel_mode: fixed takes party.panel verbatim ---"
D="$WORK/ac7b"; mkfixture "$D" panel_mode=fixed panel="[party-security, party-po]"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "The classifier said deep and must be ignored."}
EOF
runp "$D" --json
assert_eq "AC7 fixed exit 0" "0" "$RC"
assert_eq "AC7 fixed tier_source" "fixed" "$(field_of tier_source)"
assert_eq "AC7 fixed tier is not the stub's" "fixed" "$(field_of tier)"
assert_eq "AC7 fixed roster is party.panel, ranked" "party-po,party-security" "$(seats_of)"
assert_no_grep "AC7 fixed did not adopt the stub's rationale" "must be ignored" "$OUT"
if [[ -e "$D/changes/$CHANGE/party/.classifier-requested" ]]; then
  fail "AC7 fixed left a classifier-request marker"
else
  pass "AC7 fixed requested no classifier turn"
fi
echo

# ── AC8 / Edge Case 9 — the cache is keyed on the proposal, not the clock ─────
echo "--- AC8: a second panel run reuses panel.json; --repanel re-resolves ---"
D="$WORK/ac8"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
first="$(cat "$OUT")"
# Remove the answer entirely. A run that consults the classifier would now exit
# 10 (or fall back to standard); a cache hit returns the identical document.
rm -f "$D/changes/$CHANGE/party/classification.json"
runp "$D" --json
assert_eq "AC8 re-run exit 0 with no classification.json present" "0" "$RC"
assert_eq "AC8 re-run returns the identical roster" "$first" "$(cat "$OUT")"
# A *different* answer still does not move a cached panel.
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Changed my mind."}
EOF
runp "$D" --json
assert_eq "AC8 a new classification does not disturb the cache" "thin" "$(field_of tier)"
runp "$D" --repanel --json
assert_eq "AC8 --repanel re-resolves" "deep" "$(field_of tier)"
assert_eq "AC8 --repanel roster grew" "5" "$(count_of)"

echo "--- EC9: editing proposal.md changes the sig and forces re-classification ---"
D="$WORK/ec9"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "EC9 first classification" "thin" "$(field_of tier)"
sig1="$(field_of sig)"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "The proposal grew a migration section."}
EOF
printf '\n## Migration\n\nRewrite the schema.\n' >> "$D/changes/$CHANGE/proposal.md"
runp "$D" --json
assert_eq "EC9 an edited proposal re-classifies without --repanel" "deep" "$(field_of tier)"
if [[ "$(field_of sig)" != "$sig1" ]]; then pass "EC9 sig changed with the proposal"
else fail "EC9 sig changed with the proposal (still '$sig1')"; fi
echo

# ── AC15 / FR17 — the block-scoped config read (the T2 regression) ────────────
# The defect this pins: the shared `yaml_val` reduces `party.models` to `models:`
# and greps the whole file, so with a top-level `models:` block present it
# returns planning/coding/review. The fixture config carries BOTH blocks, and
# the top-level one carries decoy `party-visionary:` / `party-po:` keys, so a
# regression to `yaml_val` resolves a seat to the decoy (last-component grep) or
# to nothing at all, falling through to the charter's sentinel. Both are asserted.
echo "--- AC15: party.models resolves inside the party block, not the top-level one ---"
D="$WORK/ac15"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Every seat, so every model is exercised."}
EOF
runp "$D" --json
vis="$(models_of party-visionary)"
po="$(models_of party-po)"
assert_eq "AC15 party-visionary → party.models value" "fable" "$vis"
assert_eq "AC15 party-po → party.models value" "sonnet" "$po"
assert_eq "AC15 party-architect → party.models value" "opus" "$(models_of party-architect)"
for leak in "DECOY-top-level-models" "anthropic/claude-opus-4-8" "anthropic/claude-sonnet-5"; do
  if [[ "$vis" == "$leak" || "$po" == "$leak" ]]; then
    fail "AC15 a top-level models: value leaked into a seat ('$leak')"
  else
    pass "AC15 no leak from the top-level models: block ('$leak')"
  fi
done
# The other way a regression hides: party_val returns nothing and seat_model
# silently falls through to the charter frontmatter, which still looks plausible.
assert_no_grep "AC15 no seat fell through to the charter frontmatter" "charter-" "$OUT"
echo

# ── Edge Case 3 — an unknown seat is dropped, not fatal ───────────────────────
echo "--- EC3: a seat with no agents/<name>.md is dropped and the panel continues ---"
D="$WORK/ec3"; mkfixture "$D" panel_mode=fixed panel="[party-po, party-architect, party-nonexistent]"
runp "$D" --json
assert_eq "EC3 exit 0 — the panel is not aborted" "0" "$RC"
assert_grep "EC3 warns on stderr" "^WARN: no agent definition for seat 'party-nonexistent'" "$ERR"
assert_eq "EC3 dropped records the unknown seat" \
  "party-nonexistent:no-definition" "$(dropped_of)"
assert_eq "EC3 the known seats survive" "party-po,party-architect" "$(seats_of)"
echo

# ── Edge Case 4 — min_seats > max_seats is a config error, not a panel error ──
echo "--- EC4: min_seats > max_seats warns and uses the 2/6 defaults ---"
D="$WORK/ec4"; mkfixture "$D" min_seats=5 max_seats=2
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Deep."}
EOF
runp "$D" --json
assert_eq "EC4 exit 0" "0" "$RC"
assert_grep "EC4 warns and names the defaults" "using the defaults 2/6" "$ERR"
assert_eq "EC4 the deep roster is unclamped by the bad config" "5" "$(count_of)"
echo

# ── Edge Case 1 — an empty proposal is not a thin one ─────────────────────────
echo "--- EC1: missing or empty proposal.md exits 2 ---"
D="$WORK/ec1a"; mkfixture "$D"
rm -f "$D/changes/$CHANGE/proposal.md"
runp "$D" --json
assert_eq "EC1 missing proposal exits 2" "2" "$RC"
assert_grep "EC1 missing proposal says so" "Proposal not found" "$ERR"

D="$WORK/ec1b"; mkfixture "$D"
: > "$D/changes/$CHANGE/proposal.md"
runp "$D" --json
assert_eq "EC1 empty proposal exits 2" "2" "$RC"
assert_grep "EC1 empty proposal says so" "Proposal is empty" "$ERR"
if [[ -e "$D/changes/$CHANGE/party/panel.json" ]]; then
  fail "EC1 an empty proposal must not produce a panel.json"
else
  pass "EC1 no panel.json written for an empty proposal"
fi
echo

# ── Edge Case 10 — --json survives a rationale with quotes and newlines ───────
echo "--- EC10: an escaped quote and a newline survive into panel.json ---"
D="$WORK/ec10"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "It says \"trivial\" but it is not.\nTwo subsystems change."}
EOF
runp "$D" --json
assert_eq "EC10 exit 0" "0" "$RC"
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$D/changes/$CHANGE/party/panel.json"; then
  pass "EC10 panel.json parses under python3"
else
  fail "EC10 panel.json parses under python3"
fi
assert_eq "EC10 rationale round-trips verbatim" \
  "$(printf 'It says "trivial" but it is not.\nTwo subsystems change.')" "$(field_of rationale)"
echo

# ── AC9 — one upheld BLOCK is CHANGES_REQUESTED; withdrawing it is APPROVED ───
echo "--- AC9: an upheld BLOCK vs. the same BLOCK withdrawn ---"
D="$WORK/ac9"; mkfixture "$D"
add_finding "$D" 2 party-security BLOCK upheld "The token is logged in plaintext."
add_finding "$D" 2 party-po NOTE upheld "No objection on value."
runt "$D"
assert_eq "AC9 upheld BLOCK verdict" "CHANGES_REQUESTED" "$(cat "$OUT")"
assert_eq "AC9 exit 0 with party.block: false (party mode informs)" "0" "$RC"

D="$WORK/ac9b"; mkfixture "$D"
add_finding "$D" 2 party-security BLOCK "withdrawn — the log line is redacted upstream" \
  "The token is logged in plaintext."
add_finding "$D" 2 party-po NOTE upheld "No objection on value."
runt "$D"
assert_eq "AC9 the same BLOCK, withdrawn, is APPROVED" "APPROVED" "$(cat "$OUT")"
assert_eq "AC9 withdrawn BLOCK exit 0" "0" "$RC"

echo "--- AC9: party.block: true turns CHANGES_REQUESTED into exit 1 ---"
D="$WORK/ac9c"; mkfixture "$D" block=true
add_finding "$D" 2 party-security BLOCK upheld "The token is logged in plaintext."
runt "$D"
assert_eq "AC9 blocking verdict still printed" "CHANGES_REQUESTED" "$(cat "$OUT")"
assert_eq "AC9 exit 1 under party.block: true" "1" "$RC"

D="$WORK/ac9d"; mkfixture "$D" block=true
add_finding "$D" 2 party-po WARN upheld "The cheaper option is not costed."
runt "$D"
assert_eq "AC9 party.block: true does not fail a non-blocking verdict" "0" "$RC"
echo

# ── AC10 — the WARN arithmetic ────────────────────────────────────────────────
echo "--- AC10: two roles warn → APPROVED_WITH_NOTES; one role warns once → APPROVED ---"
D="$WORK/ac10a"; mkfixture "$D"
add_finding "$D" 2 party-po WARN upheld "The do-nothing option is not costed."
add_finding "$D" 2 party-ba WARN upheld "The evidence is one anecdote."
runt "$D"
assert_eq "AC10 two distinct roles with an upheld WARN" "APPROVED_WITH_NOTES" "$(cat "$OUT")"

D="$WORK/ac10b"; mkfixture "$D"
add_finding "$D" 2 party-po WARN upheld "The do-nothing option is not costed."
runt "$D"
assert_eq "AC10 a single upheld WARN from one role" "APPROVED" "$(cat "$OUT")"

D="$WORK/ac10c"; mkfixture "$D"
add_finding "$D" 2 party-po WARN upheld "Objection one."
add_finding "$D" 2 party-po WARN upheld "Objection two."
add_finding "$D" 2 party-po WARN upheld "Objection three."
runt "$D"
assert_eq "AC10 three upheld WARNs from one role" "APPROVED_WITH_NOTES" "$(cat "$OUT")"

D="$WORK/ac10d"; mkfixture "$D"
add_finding "$D" 2 party-po WARN upheld "Objection one."
add_finding "$D" 2 party-po WARN "withdrawn — costed in the appendix" "Objection two."
add_finding "$D" 2 party-ba WARN "withdrawn — the anecdote is a survey" "Objection three."
runt "$D"
assert_eq "AC10 withdrawn WARNs never reach the role count" "APPROVED" "$(cat "$OUT")"
assert_eq "AC10 --json withdrawn count" "2" \
  "$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "d['withdrawn']" )"
echo

# ── AC11 / AC12 — the report as the existing parsers read it ──────────────────
# specclaw-loop:291 counts `^### \[BLOCK\]` over the WHOLE file and :160-179
# extracts `^\*\*Verdict:\*\*`. Both are asserted here with those exact regexes.
echo "--- AC11/AC12: BLOCK count, verdict line, and Dissent placement ---"
D="$WORK/ac11"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Deep."}
EOF
runp "$D" --json >/dev/null
add_finding "$D" 2 party-security BLOCK upheld "The token is logged in plaintext."
add_finding "$D" 2 party-architect BLOCK "withdrawn — the module already exists" \
  "This duplicates the parser."
add_finding "$D" 2 party-po WARN upheld "The do-nothing option is not costed."
runr "$D"
REPORT="$D/changes/$CHANGE/party-report.md"
assert_eq "AC11 report exit 0" "0" "$RC"
assert_eq "AC11 grep -cE '^### \\[BLOCK\\]' counts upheld BLOCKs only" "1" \
  "$(grep -cE '^### \[BLOCK\]' "$REPORT")"
assert_eq "AC11 the verdict line is extractable" "**Verdict:** CHANGES_REQUESTED" \
  "$(grep -E '^\*\*Verdict:\*\*' "$REPORT")"
assert_eq "AC12 the withdrawn BLOCK is demoted, not deleted" "1" \
  "$(grep -cE '^### \[WITHDRAWN BLOCK\]' "$REPORT")"
# Section placement: upheld above `## Dissent`, withdrawn below it.
assert_eq "AC12 the withdrawn finding sits under ## Dissent" "1" \
  "$(sed -n '/^## Dissent/,$p' "$REPORT" | grep -cE '^### \[WITHDRAWN BLOCK\]')"
assert_eq "AC12 the Findings section holds only upheld findings" "0" \
  "$(sed -n '/^## Findings/,/^## Dissent/p' "$REPORT" | grep -cE 'WITHDRAWN')"
assert_grep "AC11 the panel line names the seats and their models" \
  '^\*\*Panel:\*\* .*party-visionary\(fable\)' "$REPORT"
assert_grep "AC11 the tier line names tier and source" '^\*\*Tier:\*\* deep \(classifier\)' "$REPORT"

# AC11, the same defect class as #61: a panelist whose **Quotes:** evidence is a
# fenced copy of the report grammar. The fenced `### [BLOCK]` is somebody else's
# example, and the fenced `**Status:** withdrawn` is not this finding's status —
# but specclaw-loop:291 greps the whole file, so an un-defused quote would pin
# the review gate red forever on a report with no blockers in it.
D="$WORK/ac11b"; mkfixture "$D"
mkdir -p "$D/changes/$CHANGE/party/findings-r2"
cat > "$D/changes/$CHANGE/party/findings-r2/party-po.md" <<'EOF'
### [WARN] party-po — the proposal pastes the report grammar inline
**Quotes:**
```markdown
### [BLOCK] party-security — an example blocker, quoted as evidence
**Status:** withdrawn — a quoted example, not this finding's status
```
**Problem:** the grammar is duplicated in prose.
**Fix:** reference the agent file instead.
**Status:** upheld
EOF
runt "$D"
assert_eq "AC11 a fenced example does not become a finding" "APPROVED" "$(cat "$OUT")"
assert_eq "AC11 a fenced Status: line does not withdraw the real finding" "0" \
  "$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "d['withdrawn']" )"
runr "$D"
REPORT="$D/changes/$CHANGE/party-report.md"
assert_eq "AC11 the quoted BLOCK is defused for grep -cE '^### \\[BLOCK\\]'" "0" \
  "$(grep -cE '^### \[BLOCK\]' "$REPORT")"
assert_grep "AC11 the quote survives, only its left margin is spent" \
  '^  ### \[BLOCK\] party-security' "$REPORT"
echo

# ── Edge Case 5 — everything withdrawn ────────────────────────────────────────
echo "--- EC5: all findings withdrawn → APPROVED and 'No upheld findings.' ---"
D="$WORK/ec5"; mkfixture "$D"
add_finding "$D" 2 party-security BLOCK "withdrawn — misread the config" "A plaintext token."
add_finding "$D" 2 party-po WARN "withdrawn — the cost is in the appendix" "Uncosted."
runt "$D"
assert_eq "EC5 verdict" "APPROVED" "$(cat "$OUT")"
runr "$D"
REPORT="$D/changes/$CHANGE/party-report.md"
assert_eq "EC5 report exit 0" "0" "$RC"
assert_eq "EC5 empty Findings section says so" "1" \
  "$(sed -n '/^## Findings/,/^## Dissent/p' "$REPORT" | grep -c '^No upheld findings\.$')"
assert_eq "EC5 every withdrawal is carried in Dissent" "2" \
  "$(sed -n '/^## Dissent/,$p' "$REPORT" | grep -cE '^### \[WITHDRAWN ')"
assert_eq "EC5 no live BLOCK is counted" "0" "$(grep -cE '^### \[BLOCK\]' "$REPORT")"
echo

# ── Edge Case 6 — a seat that filed nothing ───────────────────────────────────
echo "--- EC6: a seated panelist with no findings file is 'unheard'; the tally proceeds ---"
D="$WORK/ec6"; mkfixture "$D"
runp "$D" --panel deep --json >/dev/null
add_finding "$D" 2 party-po WARN upheld "The do-nothing option is not costed."
runt "$D"
assert_eq "EC6 the tally proceeds on the seats that spoke" "APPROVED" "$(cat "$OUT")"
assert_eq "EC6 exit 0 — an unheard seat does not block" "0" "$RC"
unheard="$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "','.join(d['unheard'])" )"
assert_eq "EC6 --json names every silent seat" \
  "party-architect,party-ba,party-visionary,party-security" "$unheard"
runr "$D"
REPORT="$D/changes/$CHANGE/party-report.md"
assert_grep "EC6 the report records the unheard seats" '^\*\*Unheard:\*\* .*party-visionary' "$REPORT"
assert_eq "EC6 the report still carries a verdict" "**Verdict:** APPROVED" \
  "$(grep -E '^\*\*Verdict:\*\*' "$REPORT")"

# Regression: "unheard" is judged on the scan stream, not on file size. A seat
# answering in prose ("I have no objections, honestly.") writes a non-empty file
# containing no finding, so the original `[[ -s ]]` test called it heard while
# the scanner yielded nothing for it — the panel silently lost a seat with no
# trace in the report, which is the exact silence FR10 forbids.
printf 'I have no objections, honestly.\n' > "$D/changes/$CHANGE/party/findings-r2/party-architect.md"
unheard="$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "','.join(d['unheard'])" )"
case "$unheard" in
  *party-architect*) pass "EC6 a prose-only answer counts as unheard, not as heard" ;;
  *) fail "EC6 a prose-only answer counts as unheard — got '$unheard'" ;;
esac
runr "$D"
assert_grep "EC6 the report names the prose-only seat" \
  '^\*\*Unheard:\*\* .*party-architect' "$REPORT"
echo

# ── Edge Case 7 — rounds: 1 disables rebuttal ─────────────────────────────────
echo "--- EC7: rounds: 1 reads findings-r1 and treats every finding as upheld ---"
D="$WORK/ec7"; mkfixture "$D" rounds=1
# Round 1 is the final word, so even a `withdrawn` marker in it counts as upheld —
# nobody was given the chance to withdraw, so nothing may be dropped silently.
add_finding "$D" 1 party-security BLOCK "withdrawn — nobody could have withdrawn this" \
  "The token is logged in plaintext."
# A round-2 file that must be ignored entirely under rounds: 1.
add_finding "$D" 2 party-po NOTE upheld "This round must not be read."
runt "$D"
assert_eq "EC7 round-1 findings decide the verdict" "CHANGES_REQUESTED" "$(cat "$OUT")"
assert_eq "EC7 --json reports rounds: 1" "1" \
  "$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "d['rounds']" )"
assert_eq "EC7 nothing counts as withdrawn" "0" \
  "$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "d['withdrawn']" )"
runr "$D"
REPORT="$D/changes/$CHANGE/party-report.md"
assert_eq "EC7 the round-1 BLOCK is a live finding in the report" "1" \
  "$(grep -cE '^### \[BLOCK\]' "$REPORT")"
assert_grep "EC7 Dissent says rebuttal was disabled" "Rebuttal was disabled" "$REPORT"
assert_no_grep "EC7 the round-2 file was not read" "This round must not be read" "$REPORT"
echo

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=================================================="
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
