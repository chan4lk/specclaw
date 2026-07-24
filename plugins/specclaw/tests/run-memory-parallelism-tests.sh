#!/usr/bin/env bash
# run-memory-parallelism-tests.sh — regression suite for the two cooperative
# concurrency helpers added by the `memory-aware-parallelism` change.
#
# Locks in:
#   specclaw-parallel-budget (FR1–FR3):
#     AC1: MemAvailable=2500MB, min_free=1024, per_agent=1024, tasks=3 -> 1.
#     AC2: no build.memory block -> parallel_tasks (3), proving opt-in.
#     AC3: extreme memory pressure clamps to >=1 (never 0/negative).
#     Edge: per_agent_mb=0 -> no divide-by-zero, falls back to parallel_tasks.
#   specclaw-browser-lock (FR5–FR7, NFR3):
#     AC4: acquire up to max returns slots; status N/N; over-cap acquire with a
#          short timeout fails open (exit 0, warns, prints `none`).
#     AC5: dead-PID slot is reclaimed on the next acquire (fast, no full wait).
#     AC6: release frees a slot; status reflects held/max; re-acquire reuses it.
#
# The budget reads MemAvailable from SPECCLAW_MEMINFO_PATH (defaults to
# /proc/meminfo) so it can be fed a deterministic fixture here.
#
# Plain bash + coreutils — no jq/bats/npm. Run from anywhere:
#   bash plugins/specclaw/tests/run-memory-parallelism-tests.sh
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

BUDGET="$BIN_DIR/specclaw-parallel-budget"
LOCK="$BIN_DIR/specclaw-browser-lock"

for b in "$BUDGET" "$LOCK"; do
  if [[ ! -f "$b" ]]; then
    echo "FATAL: missing bin script: $b" >&2
    exit 2
  fi
done

WORK="$(mktemp -d)"
# Track any sleeper PIDs we spawn to hold slots so they never outlive the suite.
SLEEPERS=()
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below.
cleanup() {
  local p
  for p in "${SLEEPERS[@]:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
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

# Write a meminfo fixture reporting <mb> MemAvailable, echo its path.
# Usage: make_meminfo <specclaw_dir> <mb>
make_meminfo() {
  local mb="$2" path="$1/meminfo"
  {
    printf 'MemTotal:       %d kB\n' $(( mb * 1024 * 2 ))
    printf 'MemFree:        %d kB\n' $(( mb * 1024 / 2 ))
    printf 'MemAvailable:   %d kB\n' $(( mb * 1024 ))
  } > "$path"
  echo "$path"
}

echo "=== specclaw memory-aware-parallelism regression suite ==="
echo "bin:  $BIN_DIR"
echo "work: $WORK"
echo

# ─────────────────────────────────────────────────────────────────────────────
# specclaw-parallel-budget
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 1 (AC1): budget = floor((2500-1024)/1024) clamped to tasks=3 -> 1 ---"
b1="$WORK/budget-ac1"
mkdir -p "$b1"
cat > "$b1/config.yaml" <<'EOF'
build:
  parallel_tasks: 3
  memory:
    min_free_mb: 1024
    per_agent_mb: 1024
EOF
mem1="$(make_meminfo "$b1" 2500)"
out="$(SPECCLAW_MEMINFO_PATH="$mem1" "$BUDGET" "$b1")"
assert_eq "AC1 budget under 2500MB" "1" "$out"
echo

echo "--- Case 2 (AC2): no build.memory block -> parallel_tasks (3), opt-in ---"
b2="$WORK/budget-ac2"
mkdir -p "$b2"
cat > "$b2/config.yaml" <<'EOF'
build:
  parallel_tasks: 3
EOF
# Even with a tight fixture, absence of the memory block means NO gating.
mem2="$(make_meminfo "$b2" 1200)"
out="$(SPECCLAW_MEMINFO_PATH="$mem2" "$BUDGET" "$b2")"
assert_eq "AC2 opt-in returns parallel_tasks" "3" "$out"
echo

echo "--- Case 3 (AC3): extreme memory pressure clamps to >=1 ---"
b3="$WORK/budget-ac3"
mkdir -p "$b3"
cat > "$b3/config.yaml" <<'EOF'
build:
  parallel_tasks: 3
  memory:
    min_free_mb: 1024
    per_agent_mb: 1024
EOF
# MemAvailable below min_free -> raw budget negative; must clamp to 1, never <=0.
mem3="$(make_meminfo "$b3" 500)"
out="$(SPECCLAW_MEMINFO_PATH="$mem3" "$BUDGET" "$b3")"
assert_eq "AC3 clamp under extreme pressure" "1" "$out"
echo

echo "--- Case 4 (edge): per_agent_mb=0 -> no divide-by-zero, falls back ---"
b4="$WORK/budget-edge0"
mkdir -p "$b4"
cat > "$b4/config.yaml" <<'EOF'
build:
  parallel_tasks: 3
  memory:
    min_free_mb: 1024
    per_agent_mb: 0
EOF
mem4="$(make_meminfo "$b4" 2500)"
out="$(SPECCLAW_MEMINFO_PATH="$mem4" "$BUDGET" "$b4")"; rc=$?
assert_eq "edge per_agent_mb=0 falls back to parallel_tasks" "3" "$out"
if [[ "$rc" -eq 0 ]]; then
  pass "edge per_agent_mb=0 exits 0 (no crash)"
else
  fail "edge per_agent_mb=0 exits 0 (rc=$rc)"
fi
echo

# ─────────────────────────────────────────────────────────────────────────────
# specclaw-browser-lock — use a short timeout so the fail-open path is fast.
# ─────────────────────────────────────────────────────────────────────────────

echo "--- Case 5 (AC4): acquire up to max, status N/N, over-cap fails open ---"
l1="$WORK/lock-ac4"
mkdir -p "$l1"
cat > "$l1/config.yaml" <<'EOF'
verify:
  playwright:
    max_browsers: 2
EOF
# Hold both slots with live PIDs (background sleepers). The helper stamps its
# OWN pid on acquire, so to keep slots live independently we claim the slot dirs
# directly with sleeper PIDs — matching the on-disk format the helper reads.
pool="$l1/.locks/playwright"
mkdir -p "$pool"
sleep 300 & p1=$!; SLEEPERS+=("$p1")
sleep 300 & p2=$!; SLEEPERS+=("$p2")
mkdir -p "$pool/slot-1" "$pool/slot-2"
echo "$p1" > "$pool/slot-1/pid"
echo "$p2" > "$pool/slot-2/pid"

status="$("$LOCK" "$l1" status)"
assert_eq "AC4 status reflects full pool" "2/2" "$status"

# Over-cap acquire with a short timeout must fail open: exit 0, print `none`, warn.
start=$SECONDS
out="$(SPECCLAW_BROWSER_LOCK_TIMEOUT=1 "$LOCK" "$l1" acquire 2>"$WORK/ac4.err")"; rc=$?
elapsed=$(( SECONDS - start ))
assert_eq "AC4 over-cap prints none" "none" "$out"
if [[ "$rc" -eq 0 ]]; then
  pass "AC4 over-cap exits 0 (fail-open)"
else
  fail "AC4 over-cap exits 0 (rc=$rc)"
fi
if grep -qi "timed out" "$WORK/ac4.err"; then
  pass "AC4 over-cap warns on timeout"
else
  fail "AC4 over-cap warns on timeout (stderr: $(cat "$WORK/ac4.err"))"
fi
if [[ "$elapsed" -le 5 ]]; then
  pass "AC4 over-cap returns within bounded timeout (${elapsed}s)"
else
  fail "AC4 over-cap returns within bounded timeout (${elapsed}s)"
fi
echo

echo "--- Case 6 (AC5): dead-PID slot reclaimed on next acquire, no full wait ---"
l2="$WORK/lock-ac5"
mkdir -p "$l2"
cat > "$l2/config.yaml" <<'EOF'
verify:
  playwright:
    max_browsers: 2
EOF
pool2="$l2/.locks/playwright"
mkdir -p "$pool2/slot-1" "$pool2/slot-2"
# slot-1 held by a live sleeper; slot-2 stamped with a guaranteed-dead PID.
sleep 300 & p3=$!; SLEEPERS+=("$p3")
echo "$p3" > "$pool2/slot-1/pid"
# Spawn+reap a process to obtain a PID that is certainly not alive.
sleep 0 & dead=$!; wait "$dead" 2>/dev/null || true
echo "$dead" > "$pool2/slot-2/pid"

start=$SECONDS
# Long timeout on purpose: reclaim must succeed FAST, well before it.
out="$(SPECCLAW_BROWSER_LOCK_TIMEOUT=30 "$LOCK" "$l2" acquire 2>/dev/null)"; rc=$?
elapsed=$(( SECONDS - start ))
assert_eq "AC5 reclaims dead slot-2" "slot-2" "$out"
if [[ "$rc" -eq 0 ]]; then
  pass "AC5 acquire exits 0"
else
  fail "AC5 acquire exits 0 (rc=$rc)"
fi
if [[ "$elapsed" -le 5 ]]; then
  pass "AC5 reclaim is fast, no full timeout wait (${elapsed}s)"
else
  fail "AC5 reclaim is fast, no full timeout wait (${elapsed}s)"
fi
# Release what we reclaimed so the pool is clean.
"$LOCK" "$l2" release slot-2 2>/dev/null || true
echo

echo "--- Case 6b (AC6): release frees a slot; status reflects held/max; re-acquire reuses it ---"
l3="$WORK/lock-ac6"
mkdir -p "$l3"
cat > "$l3/config.yaml" <<'EOF'
verify:
  playwright:
    max_browsers: 2
EOF
# Hold slot-1 with a live sleeper so `status` observes a live-PID slot. (acquire
# stamps the process that runs it; via command substitution that process exits
# immediately, so we stamp a long-lived PID directly — matching the on-disk
# format the helper reads — to exercise the held/free transition deterministically.)
pool3="$l3/.locks/playwright"
mkdir -p "$pool3/slot-1"
sleep 300 & p4=$!; SLEEPERS+=("$p4")
echo "$p4" > "$pool3/slot-1/pid"
assert_eq "AC6 status with slot-1 held" "1/2" "$("$LOCK" "$l3" status)"

# release frees it; status drops to 0/2.
"$LOCK" "$l3" release slot-1 2>/dev/null || true
assert_eq "AC6 status after release" "0/2" "$("$LOCK" "$l3" status)"

# Re-acquire must reuse the freed slot-1 (lowest free id).
slot="$("$LOCK" "$l3" acquire 2>/dev/null)"
assert_eq "AC6 re-acquire reuses slot-1" "slot-1" "$slot"
"$LOCK" "$l3" release slot-1 2>/dev/null || true
echo

echo "=================================================="
echo "$PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
