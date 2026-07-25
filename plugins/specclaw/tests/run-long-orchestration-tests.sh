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

# ─────────────────────────────────────────────────────────────────────────────
# PR-aware status — bin/specclaw-update-status (FR14)
#
# Locks in:
#   AC14: a stubbed `gh` returning an open PR renders that change's line with
#         the PR reference; a stubbed *failing* lookup leaves STATUS.md
#         byte-identical to the SPECCLAW_STATUS_NO_PR=1 baseline, exit 0.
#   AC15: proposal.md + all-[x] tasks.md + an open PR never renders as
#         "awaiting planning"; a proposal-only change with a PR is reported as
#         in flight rather than pending.
#   Edge 15: several PRs on one branch -> newest by `updatedAt`, real state
#         rendered (a merged PR must not read as open).
#   NFR1: `SPECCLAW_STATUS_NO_PR=1` skips the lookup entirely (the stub is
#         never even invoked) — the seam the unchanged-output test uses.
#   NFR5: a hanging lookup is timeout-bounded, not a hang.
#   NFR2: branch resolves as <git.branch_prefix><change>; `gh` absent falls back
#         to `az`; both absent degrades to the pre-FR14 rendering.
# ─────────────────────────────────────────────────────────────────────────────

UPDATESTATUS="$BIN_DIR/specclaw-update-status"
if [[ ! -f "$UPDATESTATUS" ]]; then
  echo "FATAL: missing bin script: $UPDATESTATUS" >&2
  exit 2
fi

# make_status_project <dir> [branch_prefix]
# A minimal `.specclaw/` tree: config.yaml (with an inline comment on the
# prefix, as templates/config.yaml ships it) plus an empty changes/ dir.
make_status_project() {
  local d="$1" prefix="${2:-specclaw/}"
  mkdir -p "$d/.specclaw/changes"
  printf 'version: 1\nproject:\n  name: "statusproj"\ngit:\n  strategy: "branch-per-change"\n  branch_prefix: "%s"      # Prefix for feature branches\n' \
    "$prefix" > "$d/.specclaw/config.yaml"
}

# add_change <project_dir> <name> [--proposal-only]
# Default shape is a fully-built change: proposal.md + tasks.md with all [x].
add_change() {
  local d="$1" name="$2" mode="${3:-}"
  mkdir -p "$d/.specclaw/changes/$name"
  printf '# Proposal\n' > "$d/.specclaw/changes/$name/proposal.md"
  [[ "$mode" == "--proposal-only" ]] && return 0
  printf -- '- [x] T1 one\n- [x] T2 two\n' > "$d/.specclaw/changes/$name/tasks.md"
}

# stub_bin <dir> <name> <body> — an executable stub on a PATH shim directory.
stub_bin() {
  local dir="$1" name="$2" body="$3"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$dir/$name"
  chmod +x "$dir/$name"
}

# STATUS.md minus the volatile `Last Updated` line, for byte-comparison.
status_body() { grep -v '^\*\*Last Updated:' "$1" || true; }

echo "--- Case 19 (AC14): a stubbed open PR renders in the change's line ---"
p19="$WORK/st-ac14"
make_status_project "$p19"
add_change "$p19" alpha
stub_bin "$p19/stub" gh 'echo "2026-07-24T09:00:00Z 123 OPEN"'
out="$(PATH="$p19/stub:$PATH" "$UPDATESTATUS" "$p19/.specclaw" 2>&1)"; rc=$?
assert_eq "AC14 update-status exits 0 with a PR found" "0" "$rc"
assert_contains "AC14 update-status reports the file it wrote" "OK: Updated" "$out"
st19="$(cat "$p19/.specclaw/STATUS.md")"
assert_contains "AC14 STATUS.md carries the PR reference" "PR #123 open" "$st19"
assert_contains "AC14 the tasks.md rendering is preserved alongside it" \
  "**alpha** — 2/2 tasks (100%)" "$st19"
echo

echo "--- Case 20 (AC14b): a failing lookup leaves output unchanged, exit 0 ---"
p20="$WORK/st-ac14b"
make_status_project "$p20"
add_change "$p20" beta
# Baseline: the PR block disabled entirely.
SPECCLAW_STATUS_NO_PR=1 "$UPDATESTATUS" "$p20/.specclaw" >/dev/null 2>&1
cp "$p20/.specclaw/STATUS.md" "$p20/baseline.md"
stub_bin "$p20/stub" gh 'echo "gh: could not determine repo" >&2; exit 1'
out="$(PATH="$p20/stub:$PATH" "$UPDATESTATUS" "$p20/.specclaw" 2>&1)"; rc=$?
assert_eq "AC14b a failing PR lookup still exits 0" "0" "$rc"
assert_eq "AC14b output is byte-identical to the no-PR baseline" \
  "$(status_body "$p20/baseline.md")" "$(status_body "$p20/.specclaw/STATUS.md")"
assert_not_contains "AC14b no PR text is invented on failure" "PR #" \
  "$(cat "$p20/.specclaw/STATUS.md")"
assert_not_contains "AC14b the lookup's stderr is not leaked into STATUS.md" \
  "could not determine repo" "$(cat "$p20/.specclaw/STATUS.md")"
echo

echo "--- Case 21 (edge 15): newest PR by updatedAt wins; merged never reads as open ---"
p21="$WORK/st-edge15"
make_status_project "$p21"
add_change "$p21" gamma
stub_bin "$p21/stub" gh 'printf "2026-07-20T10:00:00Z 100 OPEN\n2026-07-24T11:00:00Z 456 MERGED\n"'
PATH="$p21/stub:$PATH" "$UPDATESTATUS" "$p21/.specclaw" >/dev/null 2>&1; rc=$?
assert_eq "edge15 multi-PR lookup exits 0" "0" "$rc"
st21="$(cat "$p21/.specclaw/STATUS.md")"
assert_contains "edge15 newest PR is the one rendered, with its real state" "PR #456 merged" "$st21"
assert_not_contains "edge15 a merged PR never reads as open" "open" "$st21"
assert_not_contains "edge15 the older PR is not rendered" "PR #100" "$st21"
echo

echo "--- Case 22 (AC15): an open PR means in flight, never 'awaiting planning' ---"
p22="$WORK/st-ac15"
make_status_project "$p22"
add_change "$p22" delta                    # planned: proposal + all-[x] tasks
add_change "$p22" epsilon --proposal-only  # unplanned, but PR'd
stub_bin "$p22/stub" gh 'case "$*" in
  *delta*)   echo "2026-07-24T09:00:00Z 11 OPEN" ;;
  *epsilon*) echo "2026-07-24T10:00:00Z 12 OPEN" ;;
esac'
PATH="$p22/stub:$PATH" "$UPDATESTATUS" "$p22/.specclaw" >/dev/null 2>&1; rc=$?
assert_eq "AC15 update-status exits 0" "0" "$rc"
st22="$(cat "$p22/.specclaw/STATUS.md")"
assert_not_contains "AC15 no PR'd change is reported as awaiting planning" \
  "awaiting planning" "$st22"
assert_contains "AC15 the completed change keeps its task rendering + PR state" \
  "**delta** — 2/2 tasks (100%) | 0 failed | PR #11 open" "$st22"
assert_contains "AC15 a proposal-only change with a PR renders as in flight" \
  "**epsilon** — PR #12 open" "$st22"
assert_contains "AC15 both PR'd changes count as active" "**Active:** 2" "$st22"
echo

echo "--- Case 23 (NFR1): SPECCLAW_STATUS_NO_PR=1 skips the lookup entirely ---"
p23="$WORK/st-nfr1"
make_status_project "$p23"
add_change "$p23" zeta
mark23="$p23/gh-was-called"
stub_bin "$p23/stub" gh "echo called >> '$mark23'; echo \"2026-07-24T09:00:00Z 99 OPEN\""
out="$(SPECCLAW_STATUS_NO_PR=1 PATH="$p23/stub:$PATH" "$UPDATESTATUS" "$p23/.specclaw" 2>&1)"; rc=$?
assert_eq "NFR1 disabled PR block still exits 0" "0" "$rc"
if [[ -f "$mark23" ]]; then
  fail "NFR1 the lookup is never invoked when disabled (stub ran)"
else
  pass "NFR1 the lookup is never invoked when disabled"
fi
assert_not_contains "NFR1 no PR text with the block disabled" "PR #" \
  "$(cat "$p23/.specclaw/STATUS.md")"
# Same fixture, block enabled: proves the seam is what suppressed it.
PATH="$p23/stub:$PATH" "$UPDATESTATUS" "$p23/.specclaw" >/dev/null 2>&1
assert_contains "NFR1 the same fixture does render a PR when enabled" "PR #99 open" \
  "$(cat "$p23/.specclaw/STATUS.md")"
echo

echo "--- Case 24 (NFR5): a hanging lookup is timeout-bounded, not a hang ---"
p24="$WORK/st-nfr5"
make_status_project "$p24"
add_change "$p24" eta
# `exec` so the stub *is* the sleeping process: a real slow `gh` is one process,
# and `timeout` must be able to reap it without the caller waiting on a child.
stub_bin "$p24/stub" gh 'exec sleep 30'
t24=$SECONDS
PATH="$p24/stub:$PATH" "$UPDATESTATUS" "$p24/.specclaw" >/dev/null 2>&1; rc=$?
el24=$((SECONDS - t24))
assert_eq "NFR5 a hanging lookup still exits 0" "0" "$rc"
if [[ "$el24" -lt 15 ]]; then
  pass "NFR5 status generation stayed bounded (${el24}s < 15s)"
else
  fail "NFR5 status generation stayed bounded (took ${el24}s)"
fi
assert_not_contains "NFR5 a timed-out lookup contributes no PR text" "PR #" \
  "$(cat "$p24/.specclaw/STATUS.md")"
echo

echo "--- Case 25 (NFR2): the branch is <git.branch_prefix><change> ---"
p25="$WORK/st-branch"
make_status_project "$p25" "wip/"
add_change "$p25" theta
argv25="$p25/gh-argv"
stub_bin "$p25/stub" gh "printf '%s\\n' \"\$*\" >> '$argv25'; echo \"2026-07-24T09:00:00Z 5 OPEN\""
PATH="$p25/stub:$PATH" "$UPDATESTATUS" "$p25/.specclaw" >/dev/null 2>&1
assert_contains "NFR2 configured branch_prefix is used for the lookup" \
  "--head wip/theta" "$(cat "$argv25" 2>/dev/null || true)"
assert_contains "NFR2 the lookup asks for every state, so merged PRs are visible" \
  "--state all" "$(cat "$argv25" 2>/dev/null || true)"
assert_eq "NFR2 one change costs exactly one lookup (memoised per run)" "1" \
  "$(wc -l < "$argv25" | tr -d ' ')"
echo

echo "--- Case 26 (NFR2): gh absent -> az fallback; both absent -> unchanged ---"
p26="$WORK/st-az"
make_status_project "$p26"
add_change "$p26" iota
# A shim PATH with no `gh` at all — only the binaries update-status itself needs.
shim26="$p26/shim"
mkdir -p "$shim26"
for b in bash cat sed grep head sort tr date basename timeout; do
  ln -sf "$(command -v "$b")" "$shim26/$b"
done
SPECCLAW_STATUS_NO_PR=1 PATH="$shim26" "$UPDATESTATUS" "$p26/.specclaw" >/dev/null 2>&1
cp "$p26/.specclaw/STATUS.md" "$p26/baseline.md"
# Both lookups absent: degrade to the pre-FR14 rendering (NFR2).
PATH="$shim26" "$UPDATESTATUS" "$p26/.specclaw" >/dev/null 2>&1; rc=$?
assert_eq "NFR2 no gh and no az still exits 0" "0" "$rc"
assert_eq "NFR2 no lookup available -> output unchanged" \
  "$(status_body "$p26/baseline.md")" "$(status_body "$p26/.specclaw/STATUS.md")"
# Now Azure DevOps answers instead (tab-separated, as `az ... -o tsv` emits).
stub_bin "$shim26" az 'printf "2026-07-24T08:00:00Z\t77\tactive\n"'
PATH="$shim26" "$UPDATESTATUS" "$p26/.specclaw" >/dev/null 2>&1; rc=$?
assert_eq "NFR2 az fallback exits 0" "0" "$rc"
assert_contains "NFR2 az fallback renders the PR with its ADO state" "PR #77 active" \
  "$(cat "$p26/.specclaw/STATUS.md")"
echo

# ─────────────────────────────────────────────────────────────────────────────
# E2E tier — bin/specclaw-verify collect (FR7–FR9, FR13)
#
# Locks in:
#   Gate order: lint -> build -> test, then e2e per policy.
#   AC6/NFR1: a config carrying none of the new keys produces a payload
#         byte-identical to v0.5.9 (golden captured from 451301d) — no `e2e_*`
#         keys at all, not even empty ones.
#   AC7: `last` + a failing lint never runs e2e; the payload names the gate.
#   AC8: `skip` never runs e2e and says so; no state reads as a pass.
#   AC9: `always` runs e2e even when lint failed.
#   AC13: exit 137 *under a cap* -> e2e_memory_limited=true and the message
#         names the cap; exit 137 with no cap applied (wrap exit 10) -> a plain
#         failure with e2e_memory_limited=false.
#   Every e2e_state value: passed | failed | skipped_policy |
#         skipped_gate_failure | not_configured.
#   verify.heartbeat_seconds reaches run-long as `--heartbeat`.
#   Browser slot released even when the e2e command fails.
#   Edge cases:
#     8:  e2e_command set, verify.e2e absent -> default `last`.
#     9:  unrecognised verify.e2e -> warn on stderr, fall back to `last`.
#     10: e2e_command set, test_command empty -> vacuously passing, e2e runs.
#
# `systemd-run` is stubbed in both directions so neither path depends on a
# working cgroup/systemd session on the host (NFR6).
# ─────────────────────────────────────────────────────────────────────────────

VERIFY="$BIN_DIR/specclaw-verify"
if [[ ! -f "$VERIFY" ]]; then
  echo "FATAL: missing bin script: $VERIFY" >&2
  exit 2
fi

# make_verify_project <root> — a minimal `.specclaw/` tree for `verify collect`:
# spec.md with one AC and tasks.md naming one (deliberately absent) file. The
# change is always `vc`. config.yaml is written per case so the key set under
# test is exact — that is what makes the AC6 byte-comparison meaningful.
make_verify_project() {
  local root="$1"
  mkdir -p "$root/.specclaw/changes/vc"
  printf '# Spec\n\n- **AC1** — first criterion.\n' > "$root/.specclaw/changes/vc/spec.md"
  printf -- '- [x] T1 one\n  - Files: `src/specclaw-t7-absent.txt`\n' > "$root/.specclaw/changes/vc/tasks.md"
}

# Stub `systemd-run` both ways, so the cap decision is a property of the test and
# not of the host. CAP: strip the scope flags and exec the real command (so the
# usability probe passes and the wrapped command actually runs). NOCAP: always
# fail, which is exactly edge case 11 — present on PATH but unusable.
CAP_STUB="$WORK/stub-cap"
NOCAP_STUB="$WORK/stub-nocap"
stub_bin "$CAP_STUB" systemd-run 'while [[ $# -gt 0 ]]; do
  case "$1" in
    --user|--scope|-q) shift ;;
    -p) shift 2 ;;
    *) break ;;
  esac
done
exec "$@"'
stub_bin "$NOCAP_STUB" systemd-run 'exit 1'

# collect_with <stub_dir> <project_root> <errfile> — `verify collect` for change
# `vc`, with <stub_dir> shadowing systemd-run. Echoes the JSON payload.
collect_with() {
  PATH="$1:$PATH" "$VERIFY" collect "$2/.specclaw" vc 2>"$3"
}

# jval <payload> <key> — the value of a top-level `"key": …` line, unquoted.
# json_escape() collapses newlines to `\n`, so every value is one line (no jq —
# NFR3).
jval() {
  local v
  v="$(printf '%s\n' "$1" | sed -n "s/^  \"$2\": //p" | head -1 || true)"
  v="${v%,}"
  v="${v#\"}"
  v="${v%\"}"
  printf '%s' "$v"
}

echo "--- Case 27: gate order is lint -> build -> test, then e2e ---"
p27="$WORK/e2e-order"
make_verify_project "$p27"
ord27="$p27/order"
cat > "$p27/.specclaw/config.yaml" <<EOF
version: 1
build:
  lint_command: "echo lint >> $ord27"
  build_command: "echo build >> $ord27"
  test_command: "echo test >> $ord27"
  e2e_command: "echo e2e >> $ord27"
verify:
  e2e: last
EOF
out="$(collect_with "$NOCAP_STUB" "$p27" "$p27/err")"
assert_eq "gate order is lint, build, test, then e2e" "lint build test e2e" \
  "$(tr '\n' ' ' < "$ord27" | sed 's/ $//')"
assert_eq "all gates green -> e2e_state=passed" "passed" "$(jval "$out" e2e_state)"
echo

echo "--- Case 28 (AC6/NFR1): no new keys -> payload byte-identical to v0.5.9 ---"
p28="$WORK/e2e-ac6"
make_verify_project "$p28"
# Deliberately none of the five new keys: no build.e2e_command, no verify.e2e,
# no verify.heartbeat_seconds, no verify.playwright block.
cat > "$p28/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  lint_command: "echo lint-ok"
  build_command: "echo build-ok"
  test_command: "echo unit-ok"
EOF
# Golden captured by running v0.5.9's specclaw-verify (git 451301d) against this
# exact fixture. Any drift here is an NFR1 regression, not a test to update.
golden28="$(cat <<'ENDGOLDEN'
{
  "change": "vc",
  "acceptance_criteria": [
    "AC1 — first criterion."
  ],
  "changed_files": [
    {"path": "src/specclaw-t7-absent.txt", "exists": false, "content": null}
  ],
  "test_output": "unit-ok",
  "lint_output": "lint-ok",
  "build_output": "build-ok",
  "tests_passed": true,
  "lint_passed": true,
  "build_passed": true
}
ENDGOLDEN
)"
out="$(collect_with "$NOCAP_STUB" "$p28" "$p28/err")"; rc=$?
assert_eq "AC6 collect exits 0" "0" "$rc"
assert_eq "AC6 payload is byte-identical to the v0.5.9 golden" "$golden28" "$out"
assert_not_contains "AC6 not a single e2e key is emitted" "e2e" "$out"
echo

echo "--- Case 29 (AC8): verify.e2e=skip never runs e2e and cannot read as a pass ---"
p29="$WORK/e2e-skip"
make_verify_project "$p29"
cat > "$p29/.specclaw/config.yaml" <<EOF
version: 1
build:
  test_command: "echo unit-ok"
  e2e_command: "echo ran >> $p29/ran"
verify:
  e2e: skip
EOF
out="$(collect_with "$NOCAP_STUB" "$p29" "$p29/err")"
assert_eq "AC8 e2e_state=skipped_policy" "skipped_policy" "$(jval "$out" e2e_state)"
if [[ -f "$p29/ran" ]]; then
  fail "AC8 the e2e command was never executed (marker file was written)"
else
  pass "AC8 the e2e command was never executed"
fi
assert_contains "AC8 the skip states its reason" "verify.e2e=skip" "$(jval "$out" e2e_output)"
assert_contains "AC8 the skip is explicit that it is not a pass" "This is NOT a pass" \
  "$(jval "$out" e2e_output)"
assert_not_contains "AC8 a skip never emits the passed state" '"e2e_state": "passed"' "$out"
assert_eq "AC8 a skip is not a memory kill either" "false" "$(jval "$out" e2e_memory_limited)"
# The fast tier still ran and still reports independently of the e2e state.
assert_eq "AC8 the fast tier is unaffected by the skip" "true" "$(jval "$out" tests_passed)"
echo

echo "--- Case 30 (AC7): verify.e2e=last + a failing lint skips e2e, naming the gate ---"
p30="$WORK/e2e-gatefail"
make_verify_project "$p30"
cat > "$p30/.specclaw/config.yaml" <<EOF
version: 1
build:
  lint_command: "echo lint-broke; exit 9"
  e2e_command: "echo ran >> $p30/ran"
verify:
  e2e: last
EOF
out="$(collect_with "$NOCAP_STUB" "$p30" "$p30/err")"
assert_eq "AC7 lint_passed=false" "false" "$(jval "$out" lint_passed)"
assert_eq "AC7 e2e_state=skipped_gate_failure" "skipped_gate_failure" "$(jval "$out" e2e_state)"
if [[ -f "$p30/ran" ]]; then
  fail "AC7 the e2e command was never executed (marker file was written)"
else
  pass "AC7 the e2e command was never executed"
fi
assert_contains "AC7 the failing gate is named as the reason" "an earlier gate failed (lint)" \
  "$(jval "$out" e2e_output)"
assert_contains "AC7 the gate-failure skip is not a pass" "This is NOT a pass" \
  "$(jval "$out" e2e_output)"
assert_not_contains "AC7 a gate-failure skip never emits the passed state" \
  '"e2e_state": "passed"' "$out"
echo

echo "--- Case 31 (AC9): verify.e2e=always runs e2e even when lint failed ---"
p31="$WORK/e2e-always"
make_verify_project "$p31"
cat > "$p31/.specclaw/config.yaml" <<EOF
version: 1
build:
  lint_command: "echo lint-broke; exit 9"
  e2e_command: "echo ran >> $p31/ran; echo e2e-output"
verify:
  e2e: always
EOF
out="$(collect_with "$NOCAP_STUB" "$p31" "$p31/err")"
assert_eq "AC9 lint still reports failed" "false" "$(jval "$out" lint_passed)"
assert_eq "AC9 e2e ran anyway -> e2e_state=passed" "passed" "$(jval "$out" e2e_state)"
if [[ -f "$p31/ran" ]]; then
  pass "AC9 the e2e command was executed despite the failing gate"
else
  fail "AC9 the e2e command was executed despite the failing gate (no marker file)"
fi
assert_contains "AC9 e2e stdout is captured into the payload" "e2e-output" "$(jval "$out" e2e_output)"
echo

echo "--- Case 32: e2e_state=failed, and the browser slot is released anyway ---"
p32="$WORK/e2e-failed"
make_verify_project "$p32"
cat > "$p32/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  e2e_command: "echo e2e-broke; exit 4"
verify:
  e2e: always
EOF
out="$(collect_with "$NOCAP_STUB" "$p32" "$p32/err")"; rc=$?
assert_eq "failed e2e does not abort collect" "0" "$rc"
assert_eq "a non-zero e2e exit -> e2e_state=failed" "failed" "$(jval "$out" e2e_state)"
assert_contains "the failing e2e output is captured" "e2e-broke" "$(jval "$out" e2e_output)"
assert_eq "an ordinary e2e failure is not a memory kill" "false" "$(jval "$out" e2e_memory_limited)"
# The slot must come back even on the failure path: a leaked slot starves the
# pool for every later run.
held32="$(ls -d "$p32/.specclaw/.locks/playwright"/slot-* 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "the browser slot is released after a FAILING e2e run" "0" "$held32"
assert_eq "browser-lock agrees the pool is idle again" "0/2" \
  "$("$BIN_DIR/specclaw-browser-lock" "$p32/.specclaw" status)"
echo

echo "--- Case 33: e2e_state=not_configured when e2e_command is empty ---"
p33="$WORK/e2e-notconf"
make_verify_project "$p33"
cat > "$p33/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  e2e_command: ""
verify:
  e2e: last
EOF
out="$(collect_with "$NOCAP_STUB" "$p33" "$p33/err")"
assert_eq "an empty e2e_command -> e2e_state=not_configured" "not_configured" \
  "$(jval "$out" e2e_state)"
assert_contains "not_configured is explicit that it is not a pass" "This is NOT a pass" \
  "$(jval "$out" e2e_output)"
assert_not_contains "not_configured never emits the passed state" '"e2e_state": "passed"' "$out"
echo

echo "--- Case 34 (edge 8): e2e_command set, verify.e2e absent -> default 'last' ---"
p34="$WORK/e2e-edge8"
make_verify_project "$p34"
cat > "$p34/.specclaw/config.yaml" <<EOF
version: 1
build:
  test_command: "echo unit-ok"
  e2e_command: "echo ran >> $p34/ran"
EOF
out="$(collect_with "$NOCAP_STUB" "$p34" "$p34/err")"
assert_eq "edge8 the default policy runs e2e after green gates" "passed" "$(jval "$out" e2e_state)"
if [[ -f "$p34/ran" ]]; then
  pass "edge8 the e2e command ran under the defaulted policy"
else
  fail "edge8 the e2e command ran under the defaulted policy (no marker file)"
fi
assert_not_contains "edge8 the absent policy is not treated as 'skip'" "skipped_policy" "$out"
echo

echo "--- Case 35 (edge 9): an unrecognised verify.e2e warns and falls back to 'last' ---"
p35="$WORK/e2e-edge9"
make_verify_project "$p35"
cat > "$p35/.specclaw/config.yaml" <<EOF
version: 1
build:
  lint_command: "exit 9"
  e2e_command: "echo ran >> $p35/ran"
verify:
  e2e: sometimes
EOF
out="$(collect_with "$NOCAP_STUB" "$p35" "$p35/err")"; rc=$?
assert_eq "edge9 an unrecognised policy does not fail the run" "0" "$rc"
assert_contains "edge9 the unrecognised value is warned about on stderr" \
  "unrecognised value 'sometimes'" "$(cat "$p35/err")"
assert_contains "edge9 the warning names the fallback" "falling back to 'last'" "$(cat "$p35/err")"
# `last` semantics, not a silent skip: the earlier gate failed, so e2e is
# reported as gate-skipped rather than skipped_policy.
assert_eq "edge9 the fallback behaves as 'last'" "skipped_gate_failure" "$(jval "$out" e2e_state)"
assert_not_contains "edge9 an unrecognised policy is never a silent policy-skip" \
  "skipped_policy" "$out"
if [[ -f "$p35/ran" ]]; then
  fail "edge9 the failing gate still gated e2e (marker file was written)"
else
  pass "edge9 the failing gate still gated e2e"
fi
echo

echo "--- Case 36 (edge 10): an empty test_command is vacuously passing, e2e still runs ---"
p36="$WORK/e2e-edge10"
make_verify_project "$p36"
cat > "$p36/.specclaw/config.yaml" <<EOF
version: 1
build:
  lint_command: ""
  build_command: ""
  test_command: ""
  e2e_command: "echo ran >> $p36/ran"
verify:
  e2e: last
EOF
out="$(collect_with "$NOCAP_STUB" "$p36" "$p36/err")"
assert_eq "edge10 an unset fast tier still reports tests_passed=true" "true" \
  "$(jval "$out" tests_passed)"
assert_eq "edge10 e2e runs on a vacuously-green fast tier" "passed" "$(jval "$out" e2e_state)"
if [[ -f "$p36/ran" ]]; then
  pass "edge10 the e2e command ran with no fast tier configured"
else
  fail "edge10 the e2e command ran with no fast tier configured (no marker file)"
fi
echo

echo "--- Case 37 (AC13): exit 137 UNDER A CAP is reported as a memory kill ---"
p37="$WORK/e2e-ac13-capped"
make_verify_project "$p37"
cat > "$p37/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  e2e_command: "echo about-to-die; exit 137"
verify:
  e2e: always
  playwright:
    max_memory_mb: 2048
EOF
out="$(collect_with "$CAP_STUB" "$p37" "$p37/err")"
assert_eq "AC13 a capped 137 is still a failure, never a pass" "failed" "$(jval "$out" e2e_state)"
assert_eq "AC13 e2e_memory_limited=true under a cap" "true" "$(jval "$out" e2e_memory_limited)"
o37="$(jval "$out" e2e_output)"
assert_contains "AC13 the report names the memory limit" "MEMORY LIMIT EXCEEDED" "$o37"
assert_contains "AC13 the report names the configured cap value" "cap 2048M" "$o37"
assert_contains "AC13 the report rules out a test assertion failure" \
  "not a test assertion failure" "$o37"
assert_contains "AC13 the command's own output is still carried" "about-to-die" "$o37"
echo

echo "--- Case 38 (AC13b): exit 137 with NO cap applied stays a plain failure ---"
p38="$WORK/e2e-ac13-uncapped"
make_verify_project "$p38"
# Same config, same exit code — only `systemd-run` differs: the NOCAP stub is on
# PATH but fails, so `wrap` exits 10 and no cap is applied (edge case 11).
cat > "$p38/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  e2e_command: "echo about-to-die; exit 137"
verify:
  e2e: always
  playwright:
    max_memory_mb: 2048
EOF
out="$(collect_with "$NOCAP_STUB" "$p38" "$p38/err")"
assert_contains "AC13b wrap reported the uncapped emission" "systemd-run unusable" \
  "$(cat "$p38/err")"
assert_eq "AC13b an uncapped 137 is a plain failure" "failed" "$(jval "$out" e2e_state)"
assert_eq "AC13b e2e_memory_limited=false with no cap applied" "false" \
  "$(jval "$out" e2e_memory_limited)"
o38="$(jval "$out" e2e_output)"
assert_not_contains "AC13b no memory-limit claim without a cap" "MEMORY LIMIT EXCEEDED" "$o38"
assert_not_contains "AC13b no cap value is invented" "2048M" "$o38"
assert_contains "AC13b the command's output is reported as-is" "about-to-die" "$o38"
echo

echo "--- Case 39: verify.heartbeat_seconds reaches run-long as --heartbeat ---"
# A recording stub for run-long in a copied bin dir: specclaw-verify resolves
# the helper next to itself, so this is the seam that shows the exact argv.
fb39="$WORK/hb-bin"
mkdir -p "$fb39"
cp "$VERIFY" "$fb39/specclaw-verify"
argv39="$WORK/hb-argv"
: > "$argv39"
stub_bin "$fb39" specclaw-run-long "printf '%s\n' \"\$*\" >> '$argv39'
exit 0"
p39="$WORK/e2e-heartbeat"
make_verify_project "$p39"
cat > "$p39/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  test_command: "echo unit-ok"
verify:
  heartbeat_seconds: 7
EOF
"$fb39/specclaw-verify" collect "$p39/.specclaw" vc >/dev/null 2>"$p39/err"
assert_contains "configured heartbeat_seconds is passed as --heartbeat" "--heartbeat 7" \
  "$(cat "$argv39")"
assert_contains "the phase label still reaches run-long" "--phase test" "$(cat "$argv39")"
# Absent key -> no flag at all, so run-long applies its own 60s default (NFR1).
: > "$argv39"
p39b="$WORK/e2e-heartbeat-absent"
make_verify_project "$p39b"
printf 'version: 1\nbuild:\n  test_command: "echo unit-ok"\n' > "$p39b/.specclaw/config.yaml"
"$fb39/specclaw-verify" collect "$p39b/.specclaw" vc >/dev/null 2>"$p39b/err"
assert_not_contains "an absent heartbeat_seconds passes no --heartbeat flag" "--heartbeat" \
  "$(cat "$argv39")"
echo

echo "--- Case 40: the configured heartbeat is honoured end to end ---"
p40="$WORK/e2e-heartbeat-live"
make_verify_project "$p40"
cat > "$p40/.specclaw/config.yaml" <<'EOF'
version: 1
build:
  test_command: "sleep 3"
verify:
  heartbeat_seconds: 1
EOF
collect_with "$NOCAP_STUB" "$p40" "$p40/err" >/dev/null
beats40="$(grep -c '^\[run-long\] ' "$p40/err" 2>/dev/null || true)"
if [[ "${beats40:-0}" -ge 2 ]]; then
  pass "a 1s heartbeat produces liveness lines on verify's stderr (got $beats40)"
else
  fail "a 1s heartbeat produces liveness lines on verify's stderr (got ${beats40:-0})"
fi
echo

echo "=================================================="
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
