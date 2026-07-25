#!/usr/bin/env bash
# Tests for shellcheck-gate.sh.
#
# A gate that cannot fail is the bug it exists to fix, so the gate itself needs
# coverage. shellcheck is stubbed on PATH: the tests assert on the gate's
# decisions, not on real shellcheck output.
#
# Bash + coreutils only, no jq.

set -uo pipefail

GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shellcheck-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass_n=0
fail_n=0
pass() { echo "PASS: $1"; pass_n=$((pass_n + 1)); }
fail() { echo "FAIL: $1"; fail_n=$((fail_n + 1)); }

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then pass "$label (= '$got')"; else
    fail "$label (expected '$want', got '$got')"; fi
}
assert_contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) pass "$label (found '$needle')" ;;
    *) fail "$label (missing '$needle' in: $hay)" ;;
  esac
}
assert_not_contains() {
  local label="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) fail "$label (unexpectedly found '$needle')" ;;
    *) pass "$label" ;;
  esac
}

# A stub shellcheck that emits the gcc-format lines it is given, and exits 1 the
# way the real one does when it finds something.
make_stub() {
  local dir="$1"; shift
  mkdir -p "$dir"
  {
    echo '#!/usr/bin/env bash'
    echo 'if [[ "$1" == "-f" && "$2" == "gcc" ]]; then'
    echo "cat <<'GCCEOF'"
    printf '%s\n' "$@"
    echo 'GCCEOF'
    echo '  exit 1'
    echo 'fi'
    echo 'echo "(tty-format output)"; exit 1'
  } > "$dir/shellcheck"
  chmod +x "$dir/shellcheck"
}

# Run the gate with a stubbed shellcheck against a temporary baseline body.
# Output lands in $GATE_OUT (a file, not an indirect assignment) and the gate's
# exit code is returned. The committed baseline is swapped out and restored.
GATE_OUT="$WORK/gate.out"
run_gate() {
  local stub_dir="$1" baseline_body="$2"
  local baseline backup rc=0
  baseline="$(dirname "$GATE")/shellcheck-baseline.txt"
  backup="$WORK/baseline.orig"
  cp "$baseline" "$backup"
  printf '%s\n' "$baseline_body" > "$baseline"
  PATH="$stub_dir:$PATH" bash "$GATE" > "$GATE_OUT" 2>&1 || rc=$?
  cp "$backup" "$baseline"
  return "$rc"
}

BUILD="plugins/specclaw/bin/specclaw-build"
LONG="plugins/specclaw/bin/specclaw-run-long"
F_BUILD="${BUILD}:97:20: note: quoted separately. [SC2295]"
F_LONG="${LONG}:42:3: warning: brand new thing. [SC9999]"

echo "=== shellcheck-gate tests ==="
echo

echo "--- Case 1: a finding absent from the baseline fails the gate ---"
make_stub "$WORK/s1" "$F_BUILD" "$F_LONG"
rc=0
run_gate "$WORK/s1" "$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "a new finding exits 1" "1" "$rc"
assert_contains "the new finding is named" "$LONG SC9999" "$out"
assert_contains "the failure is annotated for CI" "::error::" "$out"
assert_not_contains "a baselined finding is not reported as new" "$BUILD SC2295" \
  "$(printf '%s\n' "$out" | sed -n '/not present in the baseline/,$p')"
echo

echo "--- Case 2: every finding baselined -> exit 0 ---"
make_stub "$WORK/s2" "$F_BUILD"
rc=0
run_gate "$WORK/s2" "$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "a fully baselined run exits 0" "0" "$rc"
assert_contains "it says so plainly" "no new findings" "$out"
assert_not_contains "nothing is flagged as an error" "::error::" "$out"
echo

echo "--- Case 3: a fixed finding is reported but does not fail ---"
make_stub "$WORK/s3" "$F_BUILD"
rc=0
run_gate "$WORK/s3" "$BUILD SC2295
plugins/specclaw/bin/specclaw-loop SC2015" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "a stale baseline entry still exits 0" "0" "$rc"
assert_contains "the stale entry is named for pruning" \
  "plugins/specclaw/bin/specclaw-loop SC2015" "$out"
assert_contains "pruning is described as the action" "prune" "$out"
echo

echo "--- Case 4: clean shellcheck output -> exit 0, no findings ---"
make_stub "$WORK/s4"
rc=0
run_gate "$WORK/s4" "$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "no findings at all exits 0" "0" "$rc"
assert_not_contains "a clean run raises no error" "::error::" "$out"
echo

echo "--- Case 5: comments and blank lines in the baseline are ignored ---"
make_stub "$WORK/s5" "$F_BUILD"
rc=0
run_gate "$WORK/s5" "# a comment

  # an indented comment
$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "comments do not break the comparison" "0" "$rc"
assert_not_contains "a comment is never treated as a finding" "a comment" "$out"
echo

echo "--- Case 6: the same code in a different file is a NEW finding ---"
# Pairs are file-scoped: SC2295 being baselined for one script must not license
# it everywhere.
make_stub "$WORK/s6" "${LONG}:9:1: note: quoted separately. [SC2295]"
rc=0
run_gate "$WORK/s6" "$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "the same code in another file exits 1" "1" "$rc"
assert_contains "the other file is named" "$LONG SC2295" "$out"
echo

echo "--- Case 7: line-number churn alone is not a new finding ---"
# The whole point of comparing pairs rather than line numbers.
make_stub "$WORK/s7" "${BUILD}:9999:44: note: quoted separately. [SC2295]"
rc=0
run_gate "$WORK/s7" "$BUILD SC2295" || rc=$?
out="$(cat "$GATE_OUT")"
assert_eq "a moved finding does not fail the gate" "0" "$rc"
echo

echo "--- Case 8: shellcheck missing from PATH skips, and does not fail ---"
# Fail-open on a missing linter: a dev without shellcheck can still run the
# suite. CI installs it, so the gate is real there.
SHIM="$WORK/no-shellcheck"
mkdir -p "$SHIM"
for b in bash sed sort comm grep mktemp rm wc tr cat dirname cd; do
  src="$(command -v "$b" 2>/dev/null || true)"
  [[ -n "$src" ]] && ln -sf "$src" "$SHIM/$b"
done
out=""; rc=0
out="$(PATH="$SHIM" bash "$GATE" 2>&1)" || rc=$?
assert_eq "no shellcheck on PATH exits 0" "0" "$rc"
assert_contains "the skip is explained" "shellcheck not installed" "$out"
echo

echo "--- Case 9: the committed baseline is well-formed ---"
BASELINE="$(dirname "$GATE")/shellcheck-baseline.txt"
malformed="$(grep -vE '^[[:space:]]*(#|$)' "$BASELINE" |
  grep -vcE '^plugins/specclaw/bin/[A-Za-z0-9_-]+ SC[0-9]{4}$' || true)"
assert_eq "every baseline entry is '<path> <SCxxxx>'" "0" "$malformed"
dupes="$(grep -vE '^[[:space:]]*(#|$)' "$BASELINE" | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ')"
assert_eq "the baseline has no duplicate entries" "0" "$dupes"
missing="$(grep -vE '^[[:space:]]*(#|$)' "$BASELINE" | cut -d' ' -f1 | LC_ALL=C sort -u |
  while read -r f; do [[ -f "$(dirname "$GATE")/../../../$f" ]] || echo "$f"; done | wc -l | tr -d ' ')"
assert_eq "every baselined path exists in the repo" "0" "$missing"
echo

echo "=================================================="
echo "${pass_n} passed, ${fail_n} failed"
[[ "$fail_n" -eq 0 ]]
