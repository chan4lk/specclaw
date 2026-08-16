#!/usr/bin/env bash
# run-party-tests.sh — regression suite for `bin/specclaw-party` (change 032-party-mode).
#
# Covers the arithmetic half of party mode — the half a model must never decide:
# seat resolution (AC1-AC3, AC5, AC6), the fail-loud fallback (AC4), the
# override/cache paths (AC7, AC8), the block-scoped config reader (AC15) and the
# `get` subcommand that is its only public door, the charters and their models
# (AC13), the verdict tally (AC9, AC10) and the report grammar the existing
# parsers read (AC11, AC12), plus Edge Cases 1-7, 9 and 10.
#
# And the review findings closed after the fact, each with the defect named in a
# comment above its case: the FR4 drop order (Security is not the first seat
# sacrificed), zero-padded config integers read as octal, a bare-string
# `domains`, a column-0 `party.always` list, and a round-2 dispatch that failed
# after round 1 succeeded.
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
# Recognised keys: panel_mode, panel, always, always_block, always_col0,
# min_seats, max_seats, rounds, block.
mkfixture() {
  local dir="$1"; shift
  local panel_mode="dynamic" panel="[party-po, party-architect, party-ba, party-visionary]"
  local always="[]" always_block="" always_col0="" min_seats="2" max_seats="6" rounds="2" block="false"
  local kv
  for kv in "$@"; do
    case "$kv" in
      panel_mode=*)   panel_mode="${kv#*=}" ;;
      panel=*)        panel="${kv#*=}" ;;
      always=*)       always="${kv#*=}" ;;
      always_block=*) always_block="${kv#*=}" ;;
      always_col0=*)  always_col0="${kv#*=}" ;;
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
    printf '  enabled: false\n'
    printf '  default: true\n'
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
    elif [[ -n "$always_col0" ]]; then
      # The third list form: a sequence at column 0 under an indented key. Valid
      # YAML, and what yq and ruamel emit by default — so an operator who runs
      # their config through a formatter gets this shape without asking for it.
      printf '  always:\n'
      local a items=()
      read -r -a items <<< "$always_col0"
      for a in "${items[@]}"; do printf -- '- %s\n' "$a"; done
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
  "party-po,party-architect,party-ba,party-security,party-visionary" "$(seats_of)"
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

# Deferred defect (b), found during T-wave 3: the domain match was `grep -qx`,
# exact and case-sensitive. `domains` is written by a model, and a model asked
# for "security" will sooner or later answer "Security" or "SECURITY" — on which
# spelling the specialist was silently not seated and the panel still looked
# like a working thin one. Only the roster would have shown it, and only to
# someone who knew what to expect.
echo "--- AC3 (defect b): a capitalised domain still seats the specialist ---"
for spelling in Security SECURITY SeCurItY; do
  D="$WORK/ac3-case-$spelling"; mkfixture "$D"
  stub_classifier "$D" <<EOF
{"tier": "thin", "domains": ["$spelling"], "rationale": "Small, but touches the token path."}
EOF
  runp "$D" --json
  assert_eq "AC3 domains: [\"$spelling\"] seats party-security" \
    "party-po,party-architect,party-security" "$(seats_of)"
done
# The domain string is recorded as the classifier spelled it — matching is
# case-insensitive, the audit trail is verbatim.
assert_eq "AC3 the domain is recorded as written, not normalised" "SeCurItY" \
  "$(jget "','.join(d['domains'])" < "$OUT")"
# The other half of the contract: case-insensitive is not substring-insensitive.
D="$WORK/ac3-nonmatch"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": ["insecurity"], "rationale": "A different word."}
EOF
runp "$D" --json
assert_eq "AC3 a domain that merely contains 'security' does not seat it" \
  "party-po,party-architect" "$(seats_of)"
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
# The drop ORDER is asserted seat by seat, not as "visionary before architect".
# The order shipped in the first cut of this change was
#   po, architect, ba, visionary, security
# which drops the SECURITY specialist first — the one seat that is never on the
# roster by default. It is there because the classifier flagged a trust boundary
# or because the tier is deep, so a max_seats ceiling was discarding the seat
# something specifically asked for, first, silently, on the panel that needed it.
# FR4 said "Visionary first, PO/Architect last" and the code did the opposite;
# the old assertion (visionary dropped before architect) held under both orders
# and so pinned neither. This one names every drop, in order.
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
# Tail-first, and in this exact order: Visionary goes, then Security, and only
# then would BA be considered. Architect and PO are last, always.
assert_eq "AC5 dropped names the seats, the reason, and the order" \
  "party-visionary:max_seats,party-security:max_seats" "$(dropped_of)"

echo "--- AC5: max_seats: 4 on deep drops the Visionary and KEEPS the specialist ---"
D="$WORK/ac5b"; mkfixture "$D" max_seats=4
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Five subsystems."}
EOF
runp "$D" --json
assert_eq "AC5 one seat over the ceiling drops exactly one" \
  "party-visionary:max_seats" "$(dropped_of)"
assert_eq "AC5 the security specialist survives the first drop" \
  "party-po,party-architect,party-ba,party-security" "$(seats_of)"

echo "--- AC5: the same order when the specialist came from a domain flag ---"
D="$WORK/ac5c"; mkfixture "$D" max_seats=3
stub_classifier "$D" <<'EOF'
{"tier": "deep", "domains": ["security"], "rationale": "Deep, and it touches the token path."}
EOF
runp "$D" --json
assert_eq "AC5 a domain-flagged specialist is still not the first sacrifice" \
  "party-visionary:max_seats,party-security:max_seats" "$(dropped_of)"
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
  "party-po,party-architect,party-ba,party-security,party-visionary" "$(seats_of)"
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

# Deferred defect (a), found during T-wave 3: `fixed` means "the roster is in
# the config", so an empty or absent party.panel leaves nothing to seat — and
# the min_seats growth then rebuilds the head of the tier order. The result is a
# two-seat panel, which is exactly what a legitimate `thin` classification
# produces, so the operator cannot tell the typo from the judgement. It ran, it
# cost money, and it read as a deliberate choice nobody made. The behaviour is
# unchanged (a panel still convenes); what changed is that it now says so, and
# names the key rather than the symptom.
echo "--- AC7 (defect a): panel_mode: fixed with no roster warns and names the key ---"
D="$WORK/ac7c"; mkfixture "$D" panel_mode=fixed panel="[]"
runp "$D" --json
assert_eq "AC7 empty party.panel still exits 0" "0" "$RC"
assert_grep "AC7 empty party.panel names party.panel_mode" "party\.panel_mode is 'fixed'" "$ERR"
assert_grep "AC7 empty party.panel names the missing key" \
  "party\.panel is missing or empty" "$ERR"
assert_grep "AC7 empty party.panel names the config file" "config\.yaml" "$ERR"
assert_grep "AC7 empty party.panel says what the fallback roster is" \
  "party\.min_seats" "$ERR"
assert_eq "AC7 empty party.panel still yields the min_seats-grown roster" \
  "party-po,party-architect" "$(seats_of)"

echo "--- AC7 (defect a): the same warning when party.panel is absent entirely ---"
D="$WORK/ac7d"; mkfixture "$D" panel_mode=fixed
grep -v '^  panel: ' "$D/config.yaml" > "$D/config.yaml.new" && mv "$D/config.yaml.new" "$D/config.yaml"
assert_eq "AC7 the fixture really has no party.panel key" "0" \
  "$(grep -c '^  panel: ' "$D/config.yaml")"
runp "$D" --json
assert_eq "AC7 absent party.panel still exits 0" "0" "$RC"
assert_grep "AC7 absent party.panel warns too" "party\.panel is missing or empty" "$ERR"
assert_eq "AC7 absent party.panel yields the same 2-seat roster" \
  "party-po,party-architect" "$(seats_of)"
# The control: a fixed panel that IS configured must stay silent.
D="$WORK/ac7e"; mkfixture "$D" panel_mode=fixed panel="[party-po, party-security]"
runp "$D" --json
assert_no_grep "AC7 a populated party.panel does not warn" \
  "party\.panel is missing or empty" "$ERR"
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
  "party-architect,party-ba,party-security,party-visionary" "$unheard"
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

# ── `get` — the reader CLAUDE.md's invariant requires (the BLOCK) ─────────────
# CLAUDE.md: "No party config value may be read any other way — not with
# yaml_val, not with a grep in a SKILL.md, not with a one-off sed." That rule
# shipped with no mechanism behind it: propose/SKILL.md was told to read
# party.enabled and given nothing to read it with, so the only available reading
# was a whole-file one — and in the shipped template the first `enabled:` in the
# file is build.dynamic_agents.enabled, which is `false`. Party mode would be off
# while the config plainly said `true`, and the failure is indistinguishable from
# the operator having switched it off.
#
# Same fixture shape as AC15: the decoy block above `party:` declares every
# scalar key `get` is asked for, with the opposite value.
echo "--- get: every key resolves inside the party block, past an earlier decoy ---"
rung() { "$PARTY" get "$@" >"$OUT" 2>"$ERR"; RC=$?; }
D="$WORK/get"; mkfixture "$D"

# The trap is real: prove a whole-file first-hit reader would answer `false`.
assert_eq "get the fixture really traps a whole-file reader on enabled" "false" \
  "$(grep -m1 -E '^[[:space:]]*enabled:' "$D/config.yaml" | sed -E 's/.*:[[:space:]]*//')"

rung "$D" enabled
assert_eq "get enabled exit 0" "0" "$RC"
assert_eq "get enabled → the party block's value, not the decoy" "true" "$(cat "$OUT")"
rung "$D" default
assert_eq "get default → the party block's value, not the decoy" "false" "$(cat "$OUT")"
rung "$D" rounds
assert_eq "get rounds → 2, not the decoy's 99" "2" "$(cat "$OUT")"
rung "$D" block
assert_eq "get block → false, not the decoy's true" "false" "$(cat "$OUT")"
rung "$D" panel_mode
assert_eq "get panel_mode → dynamic, not the decoy's fixed" "dynamic" "$(cat "$OUT")"
rung "$D" min_seats
assert_eq "get min_seats → 2, not the decoy's 9" "2" "$(cat "$OUT")"
rung "$D" models.party-visionary
assert_eq "get models.<seat> → the party block, not the top-level models:" "fable" "$(cat "$OUT")"

echo "--- get: list keys print one item per line, whichever YAML form ---"
rung "$D" panel
assert_eq "get panel prints one seat per line (inline [a, b] form)" \
  "party-po
party-architect
party-ba
party-visionary" "$(cat "$OUT")"
D="$WORK/get-list"; mkfixture "$D" always_block="party-security party-ba"
rung "$D" always
assert_eq "get always prints one seat per line (block '- a' form)" \
  "party-security
party-ba" "$(cat "$OUT")"

echo "--- get: absent and empty keys, and --default ---"
D="$WORK/get-empty"; mkfixture "$D"
rung "$D" always
assert_eq "get on an empty list exits 0" "0" "$RC"
assert_eq "get on an empty list prints nothing" "" "$(cat "$OUT")"
rung "$D" always --default none
assert_eq "get --default fills an empty list" "none" "$(cat "$OUT")"
rung "$D" no_such_key
assert_eq "get on an absent key exits 0" "0" "$RC"
assert_eq "get on an absent key prints nothing" "" "$(cat "$OUT")"
rung "$D" no_such_key --default 7
assert_eq "get --default fills an absent key" "7" "$(cat "$OUT")"

echo "--- get: argument errors are exit 2, never a silent empty answer ---"
rung "$D" enabled --bogus
assert_eq "get rejects an unknown option" "2" "$RC"
rung "$D"
assert_eq "get without a key exits 2" "2" "$RC"
assert_grep "get without a key says what it needs" "get requires" "$ERR"
rung "$WORK/no-such-dir" enabled
assert_eq "get on a missing config exits 2" "2" "$RC"
assert_grep "get names the missing config" "Config not found" "$ERR"
echo

# ── Zero-padded config integers ───────────────────────────────────────────────
# `max_seats: 08` is a shape a human writes and a YAML formatter emits. Bash
# reads a leading zero as octal, so `[[ 08 -gt 5 ]]` aborted with "value too
# great for base" — and an aborted comparison is a FALSE one, so the clamp was
# skipped, the min>max config error went unreported, and the panel was sized by
# neither the config nor the defaults.
echo "--- 10#: min_seats: 09 > max_seats: 08 is still caught as a config error ---"
D="$WORK/pad-a"; mkfixture "$D" min_seats=09 max_seats=08
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Deep."}
EOF
runp "$D" --json
assert_eq "10# padded min>max exits 0" "0" "$RC"
assert_no_grep "10# no octal error reaches stderr" "value too great for base" "$ERR"
assert_grep "10# padded min>max is caught and named" "using the defaults 2/6" "$ERR"
assert_eq "10# padded min>max falls back to the 2/6 defaults" "5" "$(count_of)"

echo "--- 10#: min_seats: 08 / max_seats: 09 are read as 8 and 9, not as errors ---"
D="$WORK/pad-b"; mkfixture "$D" min_seats=08 max_seats=09
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Deep."}
EOF
runp "$D" --json
assert_eq "10# a padded, valid range exits 0" "0" "$RC"
assert_no_grep "10# no octal error on a valid padded range" "value too great for base" "$ERR"
assert_no_grep "10# a valid padded range is not mistaken for min>max" "using the defaults" "$ERR"
assert_eq "10# min_seats: 08 grows the panel to every definable seat" "5" "$(count_of)"

echo "--- 10#: max_seats: 03 still clamps, padded ---"
D="$WORK/pad-c"; mkfixture "$D" max_seats=03
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Deep."}
EOF
runp "$D" --json
assert_eq "10# a padded max_seats clamps like an unpadded one" \
  "party-po,party-architect,party-ba" "$(seats_of)"

echo "--- 10#: rounds: 01 is round 1, and lands in --json as valid JSON ---"
D="$WORK/pad-d"; mkfixture "$D" rounds=01
add_finding "$D" 1 party-security BLOCK "withdrawn — nobody could have withdrawn this" \
  "The token is logged in plaintext."
runt "$D"
assert_eq "10# rounds: 01 reads findings-r1" "CHANGES_REQUESTED" "$(cat "$OUT")"
assert_eq "10# rounds: 01 is normalised to 1 in --json" "1" \
  "$( "$PARTY" tally "$D" "$CHANGE" --json 2>/dev/null | jget "d['rounds']" )"
echo

# ── A bare-string `domains` ───────────────────────────────────────────────────
# json_pick_array requires a literal `[`, so `"domains": "security"` read as NO
# domains: the specialist was silently not seated, the roster still looked like a
# working thin panel, and panel.json recorded `"domains": []` — an audit trail
# saying the classifier flagged nothing. `domains` is model-written and a model
# asked for a one-element list will sometimes return the element. Accept it, and
# warn: silently repairing model output teaches nobody, and the charter is the
# thing that then needs fixing.
echo "--- domains: a bare string seats the specialist AND warns ---"
D="$WORK/dom-str"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": "security", "rationale": "Small, but touches the token path."}
EOF
runp "$D" --json
assert_eq "domains-as-string exit 0" "0" "$RC"
assert_eq "domains-as-string still seats party-security" \
  "party-po,party-architect,party-security" "$(seats_of)"
assert_eq "domains-as-string is recorded in panel.json" "security" \
  "$(jget "','.join(d['domains'])" < "$OUT")"
assert_grep "domains-as-string warns loudly on stderr" \
  'WARN: .*"domains" as a bare string' "$ERR"
assert_grep "domains-as-string names the value it read" 'security' "$ERR"

echo "--- domains: a comma-separated string is read as a list ---"
D="$WORK/dom-str2"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": "data, security", "rationale": "Two dimensions, one string."}
EOF
runp "$D" --json
assert_eq "a comma-separated domains string seats the specialist" \
  "party-po,party-architect,party-security" "$(seats_of)"
assert_eq "a comma-separated domains string records both dimensions" "data,security" \
  "$(jget "','.join(d['domains'])" < "$OUT")"

echo "--- domains: the array form is unchanged and stays silent ---"
D="$WORK/dom-arr"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": ["security"], "rationale": "The documented form."}
EOF
runp "$D" --json
assert_eq "the array form still seats the specialist" \
  "party-po,party-architect,party-security" "$(seats_of)"
assert_no_grep "the array form does not warn" 'bare string' "$ERR"

echo "--- domains: an empty array is still no domains, and still silent ---"
D="$WORK/dom-empty"; mkfixture "$D"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "domains": [], "rationale": "Nothing flagged."}
EOF
runp "$D" --json
assert_eq "an empty domains array seats no specialist" "party-po,party-architect" "$(seats_of)"
assert_no_grep "an empty domains array does not warn about a bare string" 'bare string' "$ERR"
echo

# ── party.always as a column-0 list ───────────────────────────────────────────
# The item regex demanded an indented `-`, so a column-0 sequence — valid YAML,
# and the form yq and ruamel emit by default — read as an EMPTY list. party.always
# is the operator's escape hatch for a classifier that under-read the proposal
# (design.md:282), so a silently empty `always` disabled the mitigation on the
# one run that needed it. The party_val window is what makes this safe to accept:
# /^[a-zA-Z_]/ has already left the block, so a column-0 `-` can only be an item.
echo "--- always: a column-0 list seats the forced seat ---"
D="$WORK/always-col0"; mkfixture "$D" always_col0="party-security"
assert_eq "the fixture really writes the list at column 0" "1" \
  "$(grep -c '^- party-security$' "$D/config.yaml")"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "column-0 always exit 0" "0" "$RC"
assert_eq "column-0 always seats Security at thin" \
  "party-po,party-architect,party-security" "$(seats_of)"

echo "--- always: a column-0 list with two items, both seated and ranked ---"
D="$WORK/always-col0b"; mkfixture "$D" always_col0="party-security party-visionary"
stub_classifier "$D" <<'EOF'
{"tier": "thin", "rationale": "Small."}
EOF
runp "$D" --json
assert_eq "column-0 always seats every item, in tier order" \
  "party-po,party-architect,party-security,party-visionary" "$(seats_of)"

echo "--- always: panel_mode fixed reads a column-0 party.panel too ---"
D="$WORK/panel-col0"; mkfixture "$D" panel_mode=fixed
# Same list form, on the other key the block branch backs.
python3 - "$D/config.yaml" <<'PY'
import sys
p = sys.argv[1]
src = open(p).read().replace(
    "  panel: [party-po, party-architect, party-ba, party-visionary]\n",
    "  panel:\n- party-po\n- party-security\n")
open(p, "w").write(src)
PY
runp "$D" --json
assert_eq "a column-0 party.panel is taken verbatim, not warned away" \
  "party-po,party-security" "$(seats_of)"
assert_no_grep "a column-0 party.panel does not read as missing" \
  "party\.panel is missing or empty" "$ERR"
echo

# ── A round-2 dispatch that failed after round 1 succeeded ────────────────────
# `tally` read the empty findings-r2, counted nothing, and printed APPROVED over
# live BLOCKs on disk one directory away. SKILL.md says "read the token; never
# recompute or second-guess it", so the token is the authority — and here it was
# wrong, with only a "tallying an empty panel" warning between the operator and a
# clean verdict on a proposal whose objections were never heard.
echo "--- r2: rounds 2, findings-r2 missing, findings-r1 live → refuse, do not approve ---"
D="$WORK/r2a"; mkfixture "$D"
add_finding "$D" 1 party-security BLOCK upheld "The token is logged in plaintext."
runt "$D"
assert_eq "r2 a failed round-2 dispatch exits 2" "2" "$RC"
assert_eq "r2 no verdict token is printed at all" "" "$(cat "$OUT")"
assert_no_grep "r2 APPROVED is never printed over live round-1 findings" "APPROVED" "$OUT"
assert_grep "r2 the error names findings-r2" "findings-r2" "$ERR"
assert_grep "r2 the error names findings-r1" "findings-r1" "$ERR"
assert_grep "r2 the error names the condition, not just the symptom" \
  "round 2 was not dispatched" "$ERR"
assert_grep "r2 the error offers the two ways out" "party\.rounds: 1" "$ERR"

echo "--- r2: the same when findings-r2 exists but is empty ---"
D="$WORK/r2b"; mkfixture "$D"
add_finding "$D" 1 party-po WARN upheld "The do-nothing option is not costed."
mkdir -p "$D/changes/$CHANGE/party/findings-r2"
runt "$D"
assert_eq "r2 an empty findings-r2 directory is the same failure" "2" "$RC"
assert_eq "r2 an empty findings-r2 prints no verdict" "" "$(cat "$OUT")"

echo "--- r2: --json refuses too — the JSON caller must not see a clean verdict ---"
runt "$D" --json
assert_eq "r2 --json exits 2" "2" "$RC"
assert_eq "r2 --json prints no document" "" "$(cat "$OUT")"

echo "--- r2: report still writes the audit trail, and says round 2 is missing ---"
runr "$D"
assert_eq "r2 report still exits 0 — the report is the record" "0" "$RC"
assert_grep "r2 report warns that round 2 did not run" "round 2 was not dispatched" "$ERR"
if [[ -f "$D/changes/$CHANGE/party-report.md" ]]; then
  pass "r2 report was still written"
else
  fail "r2 report was still written"
fi

echo "--- r2: the controls — a genuinely empty panel and a complete round 2 ---"
D="$WORK/r2c"; mkfixture "$D"
runt "$D"
assert_eq "r2 a panel with no findings anywhere is still APPROVED" "APPROVED" "$(cat "$OUT")"
assert_eq "r2 a genuinely empty panel still exits 0" "0" "$RC"
assert_grep "r2 an empty panel still warns it is empty" "tallying an empty panel" "$ERR"

D="$WORK/r2d"; mkfixture "$D"
add_finding "$D" 1 party-po WARN upheld "The do-nothing option is not costed."
add_finding "$D" 2 party-po WARN "withdrawn — costed in the appendix" \
  "The do-nothing option is not costed."
runt "$D"
assert_eq "r2 a complete round 2 tallies normally" "APPROVED" "$(cat "$OUT")"
assert_eq "r2 a complete round 2 exits 0" "0" "$RC"

D="$WORK/r2e"; mkfixture "$D" rounds=1
add_finding "$D" 1 party-po WARN upheld "The do-nothing option is not costed."
runt "$D"
assert_eq "r2 rounds: 1 is untouched — round 1 IS the final word" "APPROVED" "$(cat "$OUT")"
assert_eq "r2 rounds: 1 exits 0" "0" "$RC"

D="$WORK/r2f"; mkfixture "$D"
mkdir -p "$D/changes/$CHANGE/party/findings-r1"
printf 'I have no objections, honestly.\n' > "$D/changes/$CHANGE/party/findings-r1/party-po.md"
runt "$D"
assert_eq "r2 a round-1 file with no findings in it is not a failed dispatch" "APPROVED" "$(cat "$OUT")"
assert_eq "r2 a prose-only round 1 exits 0" "0" "$RC"
echo

# ── --emit-classifier-request is gone; the marker it shared is not ────────────
# The flag had no caller, no test, and propose/SKILL.md's only mention of it was
# an instruction never to use it. The `.classifier-requested` marker it consulted
# is load-bearing and stays: it is the whole reason the SECOND panel call falls
# back to `standard` instead of exiting 10 again forever.
echo "--- the removed flag: rejected as an unknown option, gone from the usage ---"
D="$WORK/flag"; mkfixture "$D"
runp "$D" --emit-classifier-request
assert_eq "--emit-classifier-request is rejected" "2" "$RC"
assert_grep "--emit-classifier-request is rejected as an unknown option" \
  "unknown option: --emit-classifier-request" "$ERR"
assert_eq "the usage text no longer advertises the flag" "0" \
  "$( "$PARTY" --help | grep -c 'emit-classifier-request' )"

echo "--- the marker survives: the handshake still converges in exactly two calls ---"
D="$WORK/marker"; mkfixture "$D"
MARK="$D/changes/$CHANGE/party/.classifier-requested"
runp "$D" --json
assert_eq "marker: the first call asks for a classifier turn" "10" "$RC"
if [[ -f "$MARK" ]]; then pass "marker: the request left the marker"
else fail "marker: the request left the marker"; fi
runp "$D" --json
assert_eq "marker: the second call falls back rather than asking again" "0" "$RC"
assert_eq "marker: the fallback tier" "standard" "$(field_of tier)"
assert_eq "marker: the fallback source" "fallback" "$(field_of tier_source)"
if [[ -f "$MARK" ]]; then fail "marker: a successful panel clears the marker"
else pass "marker: a successful panel clears the marker"; fi
# --repanel clears it, so the handshake can be re-run deliberately.
D="$WORK/marker2"; mkfixture "$D"
runp "$D" --json
runp "$D" --repanel --json
assert_eq "marker: --repanel re-asks for a classifier turn" "10" "$RC"
echo

# ── AC13 — the six real charters, read by a test for the first time ───────────
# Every other fixture charter in this file is synthetic, so the shipped agents/
# files were never opened by the suite. seat_model falls through to a charter's
# frontmatter for any seat absent from party.models, so a typo in a `model:` line
# spawns that seat on the wrong model with no error anywhere — the suite even
# asserted the ABSENCE of that fallthrough (AC15) without ever checking what it
# would produce.
echo "--- AC13: the shipped charters parse, and carry the models the spec names ---"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd)"

# fm_val <file> <key> — the frontmatter reader, the same shape seat_model uses.
fm_val() {
  awk -v k="$2" 'NR==1 && /^---[[:space:]]*$/ {fm=1; next}
       fm && /^---[[:space:]]*$/ {exit}
       fm && $0 ~ "^" k ":" {sub("^" k ":[[:space:]]*",""); print; exit}' "$1" \
    | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

# The six charters and the models AC13 names, in spec order.
for pair in party-classifier:haiku party-po:sonnet party-ba:sonnet \
            party-architect:opus party-security:opus party-visionary:fable; do
  seat="${pair%%:*}"; want="${pair##*:}"
  f="$AGENTS_DIR/$seat.md"
  if [[ -f "$f" ]]; then pass "AC13 $seat.md exists"; else fail "AC13 $seat.md exists"; continue; fi
  assert_eq "AC13 $seat opens with a frontmatter delimiter" "---" "$(head -1 "$f")"
  assert_eq "AC13 $seat closes its frontmatter" "1" \
    "$(awk 'NR>1 && /^---[[:space:]]*$/ {print "1"; exit}' "$f")"
  assert_eq "AC13 $seat name matches its filename" "$seat" "$(fm_val "$f" name)"
  for k in description tools; do
    if [[ -n "$(fm_val "$f" "$k")" ]]; then pass "AC13 $seat has a $k"
    else fail "AC13 $seat has a $k"; fi
  done
  assert_eq "AC13 $seat model" "$want" "$(fm_val "$f" model)"
done

# The fallthrough itself, against a real charter: no local agents/<seat>.md and
# no party.models entry leaves the shipped charter as the only source. The
# fixture's own charters carry a `charter-<seat>` sentinel, so `fable` here can
# only have come from plugins/specclaw/agents/party-visionary.md.
echo "--- AC13: seat_model falls through to a REAL charter's frontmatter ---"
D="$WORK/ac13-fall"; mkfixture "$D"
rm -f "$D/agents/party-visionary.md"
grep -v '^    party-visionary: ' "$D/config.yaml" > "$D/config.yaml.new"
mv "$D/config.yaml.new" "$D/config.yaml"
assert_eq "AC13 the fixture really has no party.models.party-visionary" "0" \
  "$(grep -c '^    party-visionary: ' "$D/config.yaml")"
stub_classifier "$D" <<'EOF'
{"tier": "deep", "rationale": "Every seat."}
EOF
runp "$D" --json
assert_eq "AC13 the seat survives on the plugin's own charter" "5" "$(count_of)"
assert_eq "AC13 its model comes from the real charter's frontmatter" "fable" \
  "$(models_of party-visionary)"
assert_eq "AC13 the seats that DO have party.models are unaffected" "opus" \
  "$(models_of party-architect)"
echo

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=================================================="
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
