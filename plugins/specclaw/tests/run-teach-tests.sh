#!/usr/bin/env bash
# run-teach-tests.sh — regression suite for bin/specclaw-teach.
#
# What this pins:
#
#   T1  status reports enabled/depth/gate_builds plus syllabus defaults
#   T2  `syllabus` with no argument prints the mode (default ask)
#   T3  `syllabus <mode>` adds the key to a config that predates it, then updates it in place
#   T4  an invalid syllabus mode is refused and the config is left untouched
#   T5  syllabus-path resolves teach.syllabus_dir against the project root (default docs/syllabus)
#   T6  level records provenance; assess lists `assumed` levels as needing confirmation
#   T7  the config template carries the syllabus keys
#
# Plain bash + coreutils only. Run from anywhere:
#   bash plugins/specclaw/tests/run-teach-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEACH="$(cd "$SCRIPT_DIR/../bin" && pwd)/specclaw-teach"
TEMPLATE="$(cd "$SCRIPT_DIR/../templates" && pwd)/config.yaml"

pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'PASS: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 — expected '$2', got '$3'"; fi
}
has() { # name needle haystack
  if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1 — '$2' not in '$3'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SC="$TMP/proj/.specclaw"
mkdir -p "$SC"
# A config written before the syllabus keys existed.
cat > "$SC/config.yaml" <<'EOF'
version: 1
teach:
  enabled: false
  depth: "brief"        # minimal | brief | full
  gate_builds: true
workflow:
  strict: true
EOF

# T1
out="$(bash "$TEACH" "$SC" status)"
has "T1 status has enabled" '"enabled":false' "$out"
has "T1 status has default syllabus" '"syllabus":"ask"' "$out"
has "T1 status has default syllabus_dir" '"syllabus_dir":"docs/syllabus"' "$out"

# T2
check "T2 default mode is ask" "ask" "$(bash "$TEACH" "$SC" syllabus)"

# T3
bash "$TEACH" "$SC" syllabus always >/dev/null
check "T3 missing key is added" "always" "$(bash "$TEACH" "$SC" syllabus)"
check "T3 added exactly once" "1" "$(grep -c 'syllabus:' "$SC/config.yaml")"
bash "$TEACH" "$SC" syllabus never >/dev/null
check "T3 existing key is updated in place" "never" "$(bash "$TEACH" "$SC" syllabus)"
check "T3 still exactly once" "1" "$(grep -c 'syllabus:' "$SC/config.yaml")"
check "T3 other keys untouched" 'depth: "brief"        # minimal | brief | full' "$(grep -o 'depth: .*' "$SC/config.yaml")"
check "T3 key stays inside teach block" "  syllabus: \"never\"" "$(awk '/^teach:/{f=1;next} /^[^ ]/{f=0} f && /syllabus:/' "$SC/config.yaml")"

# T4
before="$(cat "$SC/config.yaml")"
bash "$TEACH" "$SC" syllabus sometimes >/dev/null 2>&1
check "T4 invalid mode exits non-zero" "1" "$?"
check "T4 config untouched" "$before" "$(cat "$SC/config.yaml")"

# T5
check "T5 default path under project root" "$(cd "$TMP/proj" && pwd)/docs/syllabus" "$(bash "$TEACH" "$SC" syllabus-path)"
sed -i 's/^teach:$/teach:\n  syllabus_dir: "site\/learn"/' "$SC/config.yaml"
check "T5 custom relative dir" "$(cd "$TMP/proj" && pwd)/site/learn" "$(bash "$TEACH" "$SC" syllabus-path)"

# T6
bash "$TEACH" "$SC" level jest a self >/dev/null
bash "$TEACH" "$SC" level cypress b assumed >/dev/null
out="$(bash "$TEACH" "$SC" assess)"
has "T6 assumed level needs confirmation" '"needs_confirmation":["cypress"]' "$out"
has "T6 self level counted" '"self_reported":1' "$out"

# T7
has "T7 template has syllabus mode" 'syllabus: "ask"' "$(cat "$TEMPLATE")"
has "T7 template has syllabus dir" 'syllabus_dir: "docs/syllabus"' "$(cat "$TEMPLATE")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
