#!/usr/bin/env bash
# run-long-orchestration-tests.sh — regression suite for Wave 1 of the
# `long-running-test-orchestration` change: `bin/specclaw-run-long`.
#
# Locks in:
#   specclaw-run-long (FR1–FR5):
#     AC1: `sh -c 'echo hi; exit 3'` -> exit 3, `hi` in the tail, `hi` on disk.
#     AC2: 500-line command -> 100-line tail + `... (truncated, 500 total lines)`
#          marker on stdout, all 500 lines on disk.
#     AC3: --heartbeat 1 against a 3s command -> >=2 heartbeat lines on STDERR;
#          a sub-interval command emits none.
#     AC4: sidecar always written (pass and fail) with exit/duration_s/log/head/
#          dirty/cmd/interrupted, head = 40-char SHA.
#     AC5: --reuse on matching HEAD + clean tree does NOT re-execute (proven by a
#          side-effecting counter file); refuses after a new commit.
#   Stream discipline (FR2/FR3, design "stderr = liveness, stdout = payload,
#     disk = truth"): heartbeats never land on stdout.
#   Edge cases:
#     1: unwritable --log-dir -> mktemp fallback; mktemp failure too -> inline.
#     2: eval semantics survive — pipes, `&&`, `VAR=x` env prefixes.
#     3: repo with zero commits -> empty head stamp, --reuse fails closed.
#     4: dirty tree -> --reuse refuses; a sidecar recorded dirty is never reused.
#     5: log name carries a PID discriminator, so concurrent runs never collide.
#     6: heartbeat still fires when the command prints nothing.
#     7: --heartbeat 0 / non-integer clamps to the 60s default.
#     16: SIGTERM kills the child process group, writes an `interrupted=true`
#         sidecar, exits non-zero, leaves no orphan.
#
# Plain bash + coreutils — no jq/bats/npm (NFR3). Run from anywhere:
#   bash plugins/specclaw/tests/run-long-orchestration-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

RUNLONG="$BIN_DIR/specclaw-run-long"

if [[ ! -f "$RUNLONG" ]]; then
  echo "FATAL: missing bin script: $RUNLONG" >&2
  exit 2
fi

WORK="$(mktemp -d)"
# Track any background PIDs we spawn (run-long parents, sleepers) so nothing
# outlives the suite — same guard as run-memory-parallelism-tests.sh.
SLEEPERS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below.
cleanup() {
  local p
  for p in "${SLEEPERS[@]:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
  # Belt and braces: reap the marker children used by the interrupt case.
  pkill -f '^sleep 47' 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (= '$actual')"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

# assert_contains <label> <needle> <haystack>
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label (found '$needle')"
  else
    fail "$label (missing '$needle' in: $(printf '%s' "$haystack" | head -3 | tr '\n' '|'))"
  fi
}

# assert_not_contains <label> <needle> <haystack>
assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label (absent '$needle')"
  else
    fail "$label (unexpectedly found '$needle')"
  fi
}

# The captured payload minus the trailing `log: <path>` line. Needed for
# negative assertions: the log path embeds a slug of the command itself, so
# grepping raw stdout for an absent token would self-match via the filename.
payload() { grep -v '^log: ' <<<"$1" || true; }

# Read a key from a key=value sidecar (first '=' only), echo the value.
sc() {
  local file="$1" key="$2"
  sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -1 || true
}

# Newest .result sidecar in a directory.
newest_result() {
  ls -t "$1"/*.result 2>/dev/null | head -1 || true
}

# make_repo <dir> [--empty]
# A self-contained git repo so HEAD/dirty stamping is deterministic.
make_repo() {
  local d="$1" empty="${2:-}"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email "test@specclaw.invalid"
  git -C "$d" config user.name "specclaw tests"
  git -C "$d" config commit.gpgsign false
  [[ "$empty" == "--empty" ]] && return 0
  echo one > "$d/file.txt"
  git -C "$d" add file.txt
  git -C "$d" commit -qm "init"
}

echo "=== specclaw long-running-test-orchestration (Wave 1) regression suite ==="
echo "bin:  $BIN_DIR"
echo "work: $WORK"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Exit code, tail, and on-disk log
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 1 (AC1): exit code propagates; tail and disk log carry output ---"
d1="$WORK/ac1"
out="$("$RUNLONG" --log-dir "$d1" --phase t1 -- "sh -c 'echo hi; exit 3'" 2>"$d1.err")"; rc=$?
assert_eq "AC1 exit code propagates" "3" "$rc"
assert_contains "AC1 tail carries stdout" "hi" "$out"
assert_contains "AC1 stdout announces the log path" "log: $d1/" "$out"
log1="$(sed -n 's/^log: //p' <<<"$out" | head -1)"
if [[ -f "$log1" ]]; then
  pass "AC1 log file exists on disk ($log1)"
  assert_eq "AC1 on-disk log content" "hi" "$(cat "$log1")"
else
  fail "AC1 log file exists on disk (got '$log1')"
fi
echo

echo "--- Case 2 (AC1b): a passing command exits 0 ---"
d2="$WORK/ac1b"
out="$("$RUNLONG" --log-dir "$d2" --phase t2 -- "sh -c 'echo ok'" 2>/dev/null)"; rc=$?
assert_eq "AC1b passing command exits 0" "0" "$rc"
assert_contains "AC1b tail carries output" "ok" "$out"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Capped tail (FR3 / NFR4)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 3 (AC2): 500 lines -> 100-line tail + truncation marker, 500 on disk ---"
d3="$WORK/ac2"
out="$("$RUNLONG" --log-dir "$d3" --phase t3 -- "seq 1 500" 2>/dev/null)"; rc=$?
assert_eq "AC2 exit 0" "0" "$rc"
# stdout = 100 tail lines + 1 truncation marker + 1 `log:` line.
assert_eq "AC2 stdout is exactly 102 lines" "102" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "AC2 tail starts at line 401" "401" "$(printf '%s\n' "$out" | head -1)"
assert_contains "AC2 truncation marker" "... (truncated, 500 total lines)" "$out"
log3="$(sed -n 's/^log: //p' <<<"$out" | head -1)"
assert_eq "AC2 on-disk log holds all 500 lines" "500" "$(wc -l < "$log3" | tr -d ' ')"
assert_eq "AC2 on-disk log last line" "500" "$(tail -1 "$log3")"
echo

echo "--- Case 4 (AC2b): a sub-cap command is printed whole, with no marker ---"
d4="$WORK/ac2b"
out="$("$RUNLONG" --log-dir "$d4" --phase t4 -- "seq 1 5" 2>/dev/null)"
assert_eq "AC2b stdout is 5 lines + log line" "6" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_not_contains "AC2b no truncation marker" "truncated" "$out"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Heartbeats (FR2, AC3, edge cases 6 & 7) — stderr only
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 5 (AC3 + edge 6): --heartbeat 1 on a 3s silent command ---"
d5="$WORK/ac3"
mkdir -p "$d5"
out="$("$RUNLONG" --log-dir "$d5" --phase hb --heartbeat 1 -- "sleep 3" 2>"$d5/err")"; rc=$?
assert_eq "AC3 exit 0" "0" "$rc"
beats="$(grep -c 'elapsed' "$d5/err" 2>/dev/null || true)"
if [[ "${beats:-0}" -ge 2 ]]; then
  pass "AC3 at least 2 heartbeat lines on stderr (got $beats)"
else
  fail "AC3 at least 2 heartbeat lines on stderr (got ${beats:-0}: $(tr '\n' '|' < "$d5/err"))"
fi
assert_contains "AC3 heartbeat carries elapsed seconds and log line count" "log lines" "$(cat "$d5/err")"
# Edge case 6: a silent command must still produce a heartbeat, with a note.
assert_contains "edge6 silent command still heartbeats" "(no output yet)" "$(cat "$d5/err")"
# Stream discipline: heartbeats must never pollute the captured payload.
assert_not_contains "AC3 heartbeats stay off stdout" "[run-long]" "$out"
echo

echo "--- Case 6 (AC3b): a command shorter than one interval emits no heartbeat ---"
d6="$WORK/ac3b"
mkdir -p "$d6"
"$RUNLONG" --log-dir "$d6" --phase hb2 -- "echo quick" >/dev/null 2>"$d6/err"
assert_eq "AC3b zero heartbeat lines under one interval" "0" "$(grep -c 'elapsed' "$d6/err" 2>/dev/null || true)"
echo

echo "--- Case 7 (edge 7): --heartbeat 0 / non-integer clamps to the 60s default ---"
d7="$WORK/edge7"
mkdir -p "$d7"
"$RUNLONG" --log-dir "$d7" --phase z --heartbeat 0 -- "echo x" >/dev/null 2>"$d7/zero.err"; rc=$?
assert_eq "edge7 --heartbeat 0 still exits 0" "0" "$rc"
assert_contains "edge7 --heartbeat 0 warns and clamps to 60" "clamping to 60s" "$(cat "$d7/zero.err")"
"$RUNLONG" --log-dir "$d7" --phase z2 --heartbeat abc -- "sleep 2" >/dev/null 2>"$d7/nan.err"; rc=$?
assert_eq "edge7 non-integer heartbeat still exits 0" "0" "$rc"
assert_contains "edge7 non-integer heartbeat warns and clamps" "clamping to 60s" "$(cat "$d7/nan.err")"
# Clamped to 60s, a 2s command must stay silent (no busy-loop, no 0-division).
assert_eq "edge7 clamped interval emits no heartbeat for a 2s command" "0" \
  "$(grep -c 'elapsed' "$d7/nan.err" 2>/dev/null || true)"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Sidecar (FR4 / AC4)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 8 (AC4): sidecar written on PASS with every required key ---"
r8="$WORK/repo-ac4"
make_repo "$r8"
d8="$WORK/ac4-logs"
( cd "$r8" && "$RUNLONG" --log-dir "$d8" --phase ok -- "sh -c 'echo fine'" ) >/dev/null 2>&1
s8="$(newest_result "$d8")"
if [[ -n "$s8" && -f "$s8" ]]; then
  pass "AC4 sidecar exists after a pass ($(basename "$s8"))"
  assert_eq "AC4 sidecar exit=0" "0" "$(sc "$s8" exit)"
  assert_eq "AC4 sidecar cmd round-trips" "sh -c 'echo fine'" "$(sc "$s8" cmd)"
  assert_eq "AC4 sidecar interrupted=false" "false" "$(sc "$s8" interrupted)"
  assert_eq "AC4 sidecar dirty=false on a clean tree" "false" "$(sc "$s8" dirty)"
  head8="$(sc "$s8" head)"
  assert_eq "AC4 sidecar head is a 40-char SHA" "40" "${#head8}"
  assert_eq "AC4 sidecar head equals repo HEAD" "$(git -C "$r8" rev-parse HEAD)" "$head8"
  dur8="$(sc "$s8" duration_s)"
  if [[ "$dur8" =~ ^[0-9]+$ ]]; then
    pass "AC4 sidecar duration_s is an integer (= ${dur8})"
  else
    fail "AC4 sidecar duration_s is an integer (got '$dur8')"
  fi
  log8="$(sc "$s8" log)"
  if [[ -f "$log8" ]]; then
    pass "AC4 sidecar log path points at a real file"
  else
    fail "AC4 sidecar log path points at a real file (got '$log8')"
  fi
else
  fail "AC4 sidecar exists after a pass (none found in $d8)"
fi
echo

echo "--- Case 9 (AC4b): sidecar written on FAIL too, recording the exit code ---"
d9="$WORK/ac4b-logs"
( cd "$r8" && "$RUNLONG" --log-dir "$d9" --phase bad -- "sh -c 'echo boom >&2; exit 7'" ) >/dev/null 2>&1
s9="$(newest_result "$d9")"
if [[ -n "$s9" && -f "$s9" ]]; then
  pass "AC4b sidecar exists after a failure"
  assert_eq "AC4b sidecar records exit=7" "7" "$(sc "$s9" exit)"
  assert_eq "AC4b stderr of the child landed in the log" "boom" "$(cat "$(sc "$s9" log)")"
else
  fail "AC4b sidecar exists after a failure (none found in $d9)"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# --reuse (FR5, AC5, edge cases 3 & 4)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 10 (AC5): --reuse hits on matching HEAD + clean tree, misses after a commit ---"
r10="$WORK/repo-reuse"
make_repo "$r10"
d10="$WORK/reuse-logs"
ctr10="$WORK/counter-reuse"
: > "$ctr10"
SIDE="sh -c 'echo x >> $ctr10'"

( cd "$r10" && "$RUNLONG" --log-dir "$d10" --phase re -- "$SIDE" ) >/dev/null 2>&1
assert_eq "AC5 first run executes the side effect" "1" "$(wc -l < "$ctr10" | tr -d ' ')"

err10="$WORK/reuse-hit.err"
out10="$( cd "$r10" && "$RUNLONG" --log-dir "$d10" --phase re --reuse -- "$SIDE" 2>"$err10" )"; rc=$?
assert_eq "AC5 reuse hit does NOT re-execute" "1" "$(wc -l < "$ctr10" | tr -d ' ')"
assert_eq "AC5 reuse hit replays the cached exit code" "0" "$rc"
assert_contains "AC5 reuse hit says so on stderr" "reuse: sidecar HEAD matches" "$(cat "$err10")"
assert_contains "AC5 reuse hit still prints a log path on stdout" "log: " "$out10"

# A new commit invalidates the stamp.
echo two >> "$r10/file.txt"
git -C "$r10" add file.txt
git -C "$r10" commit -qm "second"
err10b="$WORK/reuse-headmiss.err"
( cd "$r10" && "$RUNLONG" --log-dir "$d10" --phase re --reuse -- "$SIDE" ) >/dev/null 2>"$err10b"
assert_eq "AC5 new commit invalidates reuse (re-executed)" "2" "$(wc -l < "$ctr10" | tr -d ' ')"
assert_contains "AC5 HEAD-mismatch is reported" "re-executing" "$(cat "$err10b")"
echo

echo "--- Case 11 (edge 4): a dirty tree refuses reuse ---"
echo dirt >> "$r10/file.txt"
err11="$WORK/reuse-dirty.err"
( cd "$r10" && "$RUNLONG" --log-dir "$d10" --phase re --reuse -- "$SIDE" ) >/dev/null 2>"$err11"
assert_eq "edge4 dirty tree re-executes" "3" "$(wc -l < "$ctr10" | tr -d ' ')"
assert_contains "edge4 dirty tree is reported" "working tree is dirty" "$(cat "$err11")"
git -C "$r10" checkout -q -- file.txt
echo

echo "--- Case 12 (edge 4b): a sidecar recorded on a dirty tree is never reused ---"
r12="$WORK/repo-cacheddirty"
make_repo "$r12"
d12="$WORK/cacheddirty-logs"
ctr12="$WORK/counter-cacheddirty"
: > "$ctr12"
SIDE12="sh -c 'echo y >> $ctr12'"
# Record the sidecar while the tree is dirty ...
echo dirt >> "$r12/file.txt"
( cd "$r12" && "$RUNLONG" --log-dir "$d12" --phase cd -- "$SIDE12" ) >/dev/null 2>&1
s12="$(newest_result "$d12")"
assert_eq "edge4b sidecar records dirty=true" "true" "$(sc "$s12" dirty)"
# ... then clean the tree: HEAD matches and the tree is clean, but the cached
# result was measured against uncommitted edits, so it must not be served.
git -C "$r12" checkout -q -- file.txt
err12="$WORK/reuse-cacheddirty.err"
( cd "$r12" && "$RUNLONG" --log-dir "$d12" --phase cd --reuse -- "$SIDE12" ) >/dev/null 2>"$err12"
assert_eq "edge4b cached-dirty sidecar re-executes" "2" "$(wc -l < "$ctr12" | tr -d ' ')"
assert_contains "edge4b cached-dirty refusal is reported" "recorded with a dirty tree" "$(cat "$err12")"
echo

echo "--- Case 13 (edge 3): repo with zero commits -> empty head stamp, reuse fails closed ---"
r13="$WORK/repo-empty"
make_repo "$r13" --empty
d13="$WORK/empty-logs"
ctr13="$WORK/counter-empty"
: > "$ctr13"
SIDE13="sh -c 'echo z >> $ctr13'"
( cd "$r13" && "$RUNLONG" --log-dir "$d13" --phase eh -- "$SIDE13" ) >/dev/null 2>&1
s13="$(newest_result "$d13")"
assert_eq "edge3 sidecar exists for a commit-less repo" "0" "$(sc "$s13" exit)"
assert_eq "edge3 head stamp is empty" "" "$(sc "$s13" head)"
err13="$WORK/reuse-nohead.err"
( cd "$r13" && "$RUNLONG" --log-dir "$d13" --phase eh --reuse -- "$SIDE13" ) >/dev/null 2>"$err13"
assert_eq "edge3 no-HEAD reuse fails closed (re-executed)" "2" "$(wc -l < "$ctr13" | tr -d ' ')"
assert_contains "edge3 no-HEAD refusal is reported" "no HEAD available" "$(cat "$err13")"
echo

# ─────────────────────────────────────────────────────────────────────────────
# eval semantics (edge case 2)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 14 (edge 2): pipes, &&, and env prefixes survive eval ---"
d14="$WORK/edge2"
out="$("$RUNLONG" --log-dir "$d14" --phase pipe -- "printf 'aaa\nbbb\nccc\n' | grep bbb" 2>/dev/null)"; rc=$?
assert_eq "edge2 pipeline exits 0" "0" "$rc"
assert_contains "edge2 pipeline output preserved" "bbb" "$out"
assert_not_contains "edge2 pipeline actually filtered" "aaa" "$(payload "$out")"

out="$("$RUNLONG" --log-dir "$d14" --phase and -- "sh -c 'exit 0' && echo second-ran" 2>/dev/null)"; rc=$?
assert_eq "edge2 && chain exits 0" "0" "$rc"
assert_contains "edge2 && chain ran the right-hand side" "second-ran" "$out"

out="$("$RUNLONG" --log-dir "$d14" --phase and2 -- "sh -c 'exit 4' && echo must-not-run" 2>/dev/null)"; rc=$?
assert_eq "edge2 && short-circuit propagates the left exit code" "4" "$rc"
assert_not_contains "edge2 && short-circuit skipped the right-hand side" "must-not-run" "$(payload "$out")"

out="$("$RUNLONG" --log-dir "$d14" --phase env -- 'FOO=bar sh -c "echo got=\$FOO"' 2>/dev/null)"; rc=$?
assert_eq "edge2 env-prefix exits 0" "0" "$rc"
assert_contains "edge2 env prefix reached the child" "got=bar" "$out"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Log-dir fail-open (edge case 1 / NFR2)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 15 (edge 1): unwritable --log-dir falls back to mktemp ---"
blocker="$WORK/not-a-dir"
: > "$blocker"           # a regular file: mkdir -p below it fails even as root
err15="$WORK/edge1.err"
out="$("$RUNLONG" --log-dir "$blocker/logs" --phase fb -- "echo fellback" 2>"$err15")"; rc=$?
assert_eq "edge1 fallback still exits 0" "0" "$rc"
assert_contains "edge1 warns about the unwritable log dir" "falling back to mktemp" "$(cat "$err15")"
assert_contains "edge1 output still captured" "fellback" "$out"
log15="$(sed -n 's/^log: //p' <<<"$out" | head -1)"
assert_not_contains "edge1 log did NOT land under the rejected dir" "$blocker" "$log15"
if [[ -n "$log15" && -f "$log15" ]]; then
  pass "edge1 fallback log exists ($log15)"
  rm -rf "$(dirname "$log15")"
else
  fail "edge1 fallback log exists (got '$log15')"
fi
echo

echo "--- Case 16 (edge 1b): mktemp failure too -> inline execution, no log/sidecar ---"
err16="$WORK/edge1b.err"
out="$(TMPDIR="$blocker" "$RUNLONG" --log-dir "$blocker/logs" --phase inline -- "echo ran-inline" 2>"$err16")"; rc=$?
assert_eq "edge1b inline execution exits with the command's code" "0" "$rc"
assert_contains "edge1b warns that it is running inline" "running inline" "$(cat "$err16")"
assert_contains "edge1b command still ran" "ran-inline" "$out"
assert_not_contains "edge1b no log path claimed" "log: " "$out"
rc=0; TMPDIR="$blocker" "$RUNLONG" --log-dir "$blocker/logs" -- "sh -c 'exit 5'" >/dev/null 2>&1 || rc=$?
assert_eq "edge1b inline execution still propagates a failure" "5" "$rc"
echo

# ─────────────────────────────────────────────────────────────────────────────
# PID discriminator (edge case 5)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 17 (edge 5): concurrent runs of the same command do not collide ---"
d17="$WORK/edge5"
mkdir -p "$d17"
CMD17="sh -c 'sleep 1; echo done'"
"$RUNLONG" --log-dir "$d17" --phase cc -- "$CMD17" >/dev/null 2>&1 &
a=$!; SLEEPERS+=("$a")
"$RUNLONG" --log-dir "$d17" --phase cc -- "$CMD17" >/dev/null 2>&1 &
b=$!; SLEEPERS+=("$b")
wait "$a"; wait "$b"
logs17="$(ls "$d17"/cc-*.log 2>/dev/null | wc -l | tr -d ' ')"
res17="$(ls "$d17"/cc-*.result 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "edge5 two concurrent runs wrote two distinct logs" "2" "$logs17"
assert_eq "edge5 two concurrent runs wrote two distinct sidecars" "2" "$res17"
assert_contains "edge5 log name carries the PID discriminator" "-${a}.log" "$(ls "$d17"/cc-*.log | tr '\n' ' ')"
# Neither truncated the other: both logs hold the full output.
bad17=0
for f in "$d17"/cc-*.log; do
  [[ "$(cat "$f")" == "done" ]] || bad17=$((bad17 + 1))
done
assert_eq "edge5 neither run truncated the other's log" "0" "$bad17"
echo

# ─────────────────────────────────────────────────────────────────────────────
# Interrupt handling (NFR7 / edge case 16)
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 18 (edge 16): SIGTERM kills the child group, writes interrupted sidecar ---"
d18="$WORK/edge16"
mkdir -p "$d18"
# NOTE: the child marker is `sleep 47`, matched with an anchored pattern
# (`^sleep 47`) so the harness's own argv never self-matches.
"$RUNLONG" --log-dir "$d18" --phase intr --heartbeat 1 -- "sleep 47" >/dev/null 2>&1 &
rl=$!; SLEEPERS+=("$rl")
# Wait for the detached child to actually be running before signalling.
spawned=0
for _ in $(seq 1 60); do
  if pgrep -f '^sleep 47' >/dev/null 2>&1; then spawned=1; break; fi
  sleep 0.1
done
assert_eq "edge16 child was spawned before the signal" "1" "$spawned"
kill -TERM "$rl" 2>/dev/null || true
rc=0; wait "$rl" || rc=$?
assert_eq "edge16 interrupted run exits non-zero" "1" "$rc"
s18="$(newest_result "$d18")"
if [[ -n "$s18" && -f "$s18" ]]; then
  pass "edge16 sidecar written on interrupt ($(basename "$s18"))"
  assert_eq "edge16 sidecar marks interrupted=true" "true" "$(sc "$s18" interrupted)"
  assert_eq "edge16 sidecar records a non-zero exit" "1" "$(sc "$s18" exit)"
  assert_contains "edge16 sidecar keeps the command string" "sleep 47" "$(sc "$s18" cmd)"
else
  fail "edge16 sidecar written on interrupt (none found in $d18)"
fi
# No orphan: the child must be gone shortly after the parent's trap runs.
orphan=1
for _ in $(seq 1 30); do
  if ! pgrep -f '^sleep 47' >/dev/null 2>&1; then orphan=0; break; fi
  sleep 0.1
done
assert_eq "edge16 no orphaned child process survives" "0" "$orphan"
echo

echo "=================================================="
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
