#!/usr/bin/env bash
# run-synth-agent-tests.sh — regression suite for `specclaw-build synth-agent`
# and the `Kind:` field added to `specclaw-parse-tasks`.
#
# Locks in the dynamic-subagents-for-build behaviors:
#   AC1: synth-agent emits valid JSON with the required keys.
#   AC2: kind/tier -> tools + cost-aware model routing
#        (docs->haiku+[Read,Write], large impl->opus, extreme gated off Fable
#        under the default opus ceiling).
#   AC8: cache reuse on unchanged task signature; invalidation on task change.
#   AC9: parse-tasks surfaces `kind` when present, empty when absent (compat).
#
# Plain bash + python3 (for JSON asserts) — no jq/bats/npm. Run from anywhere:
#   bash plugins/specclaw/tests/run-synth-agent-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
TPL_CONFIG="$(cd "$SCRIPT_DIR/.." && pwd)/templates/config.yaml"

BUILD="$BIN_DIR/specclaw-build"
PARSE_TASKS="$BIN_DIR/specclaw-parse-tasks"

for f in "$BUILD" "$PARSE_TASKS" "$TPL_CONFIG"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null || { echo "FATAL: python3 required" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then pass "$label (= '$actual')"
  else fail "$label (expected '$expected', got '$actual')"; fi
}

# jget <json-file-or-stdin-var> <python-expr on `d`> — print a field
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# Copy the shipped template config (carries build.dynamic_agents) as the specclaw dir config.
cp "$TPL_CONFIG" "$WORK/config.yaml"

# --- Fixture change with one task per kind/tier under test ---
mkdir -p "$WORK/changes/dyn"
cat > "$WORK/changes/dyn/tasks.md" <<'EOF'
### Wave 1 — mixed kinds
- [ ] `T1` — write the docs page
  - Files: README.md
  - Estimate: small
  - Kind: docs
- [ ] `T2` — implement the big engine
  - Files: src/engine.js
  - Estimate: large
  - Kind: impl
- [ ] `T3` — very hairy core rewrite
  - Files: src/core.js
  - Estimate: large
  - Kind: extreme
- [ ] `T4` — plain task no kind
  - Files: src/util.js
  - Estimate: small
EOF

echo "=== specclaw synth-agent regression suite ==="
echo "bin: $BIN_DIR"
echo

# ─── Case 1 (AC1): valid JSON with required keys ───────────────────────────────
echo "--- Case 1 (AC1): synth-agent emits valid JSON with required keys ---"
"$BUILD" synth-agent "$WORK" dyn T2 >"$WORK/t2.json" 2>"$WORK/t2.err"
if python3 -c "import json;json.load(open('$WORK/t2.json'))" 2>/dev/null; then
  keys="$(<"$WORK/t2.json" jget "','.join(sorted(d.keys()))")"
  assert_eq "T2 JSON keys" "downgrade,kind,model,role,schema_version,sig,system_prompt,task,tier,tools" "$keys"
else
  fail "T2 synth-agent emits valid JSON (stderr: $(cat "$WORK/t2.err"))"
fi
echo

# ─── Case 2 (AC2): routing matrix ──────────────────────────────────────────────
echo "--- Case 2 (AC2): kind/tier -> tools + cost-aware model ---"
# docs/small -> trivial -> haiku, tools [Read, Write]
"$BUILD" synth-agent "$WORK" dyn T1 2>/dev/null >"$WORK/t1.json"
assert_eq "T1 model (docs->haiku)" "anthropic/claude-haiku-4-5" "$(<"$WORK/t1.json" jget "d['model']")"
assert_eq "T1 tools (docs)" "Read,Write" "$(<"$WORK/t1.json" jget "','.join(d['tools'])")"
# impl/large -> complex -> opus, full tool set
assert_eq "T2 model (large impl->opus)" "anthropic/claude-opus-4-8" "$(<"$WORK/t2.json" jget "d['model']")"
assert_eq "T2 tools (impl)" "Read,Write,Edit,Bash,Grep,Glob" "$(<"$WORK/t2.json" jget "','.join(d['tools'])")"
# extreme -> Fable requested but clamped by default opus ceiling => never fable
"$BUILD" synth-agent "$WORK" dyn T3 2>/dev/null >"$WORK/t3.json"
t3model="$(<"$WORK/t3.json" jget "d['model']")"
if [[ "$t3model" == *fable* ]]; then fail "T3 must not select Fable under default opus ceiling (got $t3model)"
else pass "T3 no Fable under default ceiling (= '$t3model')"; fi
# guardrails + scope fence embedded
if grep -q "Simplicity First" "$WORK/t2.json" && grep -q "Scope fence" "$WORK/t2.json"; then
  pass "T2 system_prompt carries guardrails + scope fence"
else fail "T2 system_prompt carries guardrails + scope fence"; fi
echo

# ─── Case 3 (AC8): cache reuse + invalidation ──────────────────────────────────
echo "--- Case 3 (AC8): cache reuse on unchanged task, invalidate on change ---"
rm -f "$WORK/changes/dyn/agents/"*.json 2>/dev/null || true
"$BUILD" synth-agent "$WORK" dyn T2 >/dev/null 2>&1
m1="$(stat -c %Y "$WORK/changes/dyn/agents/T2.json")"
sig1="$(sed -n 's/.*"sig":[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/changes/dyn/agents/T2.json")"
sleep 1
"$BUILD" synth-agent "$WORK" dyn T2 >/dev/null 2>&1
m2="$(stat -c %Y "$WORK/changes/dyn/agents/T2.json")"
assert_eq "cache reuse: file not rewritten" "$m1" "$m2"
# Change the task -> signature changes, file regenerates
sed -i 's|`T2` — implement the big engine|`T2` — implement the big engine (v2)|' "$WORK/changes/dyn/tasks.md"
sleep 1
"$BUILD" synth-agent "$WORK" dyn T2 >/dev/null 2>&1
m3="$(stat -c %Y "$WORK/changes/dyn/agents/T2.json")"
sig3="$(sed -n 's/.*"sig":[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/changes/dyn/agents/T2.json")"
if [[ "$m2" != "$m3" && "$sig1" != "$sig3" ]]; then pass "cache invalidated on task change (rewrote + new sig)"
else fail "cache invalidated on task change (m2=$m2 m3=$m3 sig1=$sig1 sig3=$sig3)"; fi
echo

# ─── Case 4 (AC9): parse-tasks kind field, backward compatible ─────────────────
echo "--- Case 4 (AC9): parse-tasks surfaces kind; empty when absent ---"
allkinds="$("$PARSE_TASKS" "$WORK/changes/dyn/tasks.md" 2>/dev/null | jget "','.join(t['kind'] for t in d)")"
# T1 docs, T2 impl, T3 extreme, T4 (no kind -> empty)
assert_eq "parse-tasks kinds (last empty)" "docs,impl,extreme," "$allkinds"
echo

echo "=================================================="
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -gt 0 ]] && exit 1
exit 0
