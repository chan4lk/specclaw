#!/usr/bin/env bash
# run-bf-e2e-run-tests.sh — regression suite for specclaw-bf-e2e-run, which
# executes the E2E suite bf-e2e-architect just generated and mechanically
# patches .specclaw/e2e/e2e-report.md's Execution Results section.
#
# What this suite protects, and why each one is here:
#
#   - NEVER FABRICATES A NUMBER. A test-runner output this script cannot parse
#     must read as "NOT MEASURED", never as a guessed zero. This is the same
#     discipline the rest of this plugin applies to every bash-computed figure
#     (see specclaw-bf-quality-collect's report_blocks).
#
#   - EVERYTHING OUTSIDE THE ANCHORS IS UNTOUCHED. The report's other sections
#     were written by the agent; this script may only ever replace what sits
#     between <!-- e2e-report:execution-results:begin/end -->.
#
#   - A FAILED PRECONDITION IS RECORDED, NEVER FATAL. Missing run-config.json,
#     missing jq, a failed install command, or an empty test_cmd all write a
#     "not executed" reason into the report and exit 0 — this script's own
#     exit code is reserved for it failing to do its job (bad arguments, no
#     report to patch at all), not for the E2E suite failing or not running.
#
#   - THE TEST COMMAND NEVER RUNS AFTER A FAILED INSTALL. Asserted by checking
#     that a marker file the test command would have created is absent.
#
#   - SERVICES ALREADY RUNNING ARE LEFT ALONE. A service whose check_cmd
#     already passes is never started — asserted by checking its start_cmd's
#     side effect (a marker file) never happened.
#
#   - SERVICES ARE BROUGHT UP IN ORDER, EACH GATED ON THE ONE BEFORE. A
#     frontend service whose start_cmd only succeeds once a backend service's
#     readiness marker exists must still end up ready — proving the runner
#     waited for the first before starting the second, not fired both at once.
#
#   - A SERVICE THAT NEVER BECOMES READY IS A RECORDED REASON, NEVER FATAL, AND
#     NEVER LEAVES A PROCESS BEHIND. The test command never runs, and the
#     process the runner itself started is torn down before it exits.
#
#   - ARTIFACTS (on-failure screenshots/video) ARE COPIED WHOLE-TREE, TYPED BY
#     EXTENSION, AND NEVER FABRICATED. A missing/empty artifacts_dir reads
#     "None" with a reason, never a blank section; a "not executed" run clears
#     Artifacts the same way it clears Execution Results.
#
#   - THE HTML REPORT IS A MECHANICAL TRANSFORM OF THE FINISHED MARKDOWN, NEVER
#     A SEPARATE SOURCE OF TRUTH. Its stat cards must agree with the markdown
#     numbers exactly, and it is regenerated (never appended to) on every run.
#
#   - THE TEST SCENARIOS LIST IS FOR EVERYONE, IN FRONT OF THE FOLD, GROUPED BY
#     MODULE — NEVER BY RAW FILE PATH. A scenario's headline is its
#     plain-language summary only; the file path is real but de-emphasized,
#     moved to a small "Test file:" metadata line alongside "Evidence:" —
#     never the thing a non-technical reader sees first. Positioned before the
#     collapsed Technical Details, not inside it.
#
#   - AGENT-AUTHORED CONTENT CAN NEVER REACH THE SHELL. A title/section
#     containing `$(...)`, backticks, or `<script>` must render as inert
#     escaped text in the HTML — never get evaluated while this script builds
#     the file, and never break out of its HTML context.
#
# Bash + coreutils. jq required (this script degrades gracefully without it;
# this suite still needs it to author the run-config.json fixtures compactly,
# so it skips with a note when jq is absent).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PLUGIN_ROOT/bin/specclaw-bf-e2e-run"
TEMPLATE="$PLUGIN_ROOT/templates/e2e-report.md"

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
    *) bad "$label" "missing [$needle]" ;; esac
}
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A bare project with the report seeded from the real template (so a template
# edit that drops/renames the anchors fails this suite too, not just at
# runtime).
new_project() {
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/.specclaw/e2e" "$root/app"
  cp "$TEMPLATE" "$root/.specclaw/e2e/e2e-report.md"
}

exec_section() {
  sed -n '/execution-results:begin/,/execution-results:end/p' "$1/.specclaw/e2e/e2e-report.md"
}

artifacts_section() {
  sed -n '/artifacts:begin/,/artifacts:end/p' "$1/.specclaw/e2e/e2e-report.md"
}

rest_of_report() {
  # Everything OUTSIDE both bash-owned anchored regions (Execution Results,
  # Artifacts), for the byte-fidelity check — the agent-authored part of the
  # report that this script must never touch.
  awk '
    /execution-results:begin/ { inb=1 }
    /artifacts:begin/ { inb=1 }
    !inb { print }
    /execution-results:end/ { inb=0 }
    /artifacts:end/ { inb=0 }
  ' "$1/.specclaw/e2e/e2e-report.md"
}

echo "=================================================="
echo "specclaw-bf-e2e-run regression suite"
echo "=================================================="

# ── 1. No run-config.json ────────────────────────────────────────────────────
echo
echo "-- no run-config.json --"

R="$WORK/no-config"; new_project "$R"
BEFORE_REST="$(rest_of_report "$R")"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 even with nothing to run"
assert_contains "$OUT" "NOT EXECUTED" "and says so on stderr"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** no —" "the report records 'not executed'"
assert_contains "$SEC" "no .specclaw/e2e/run-config.json" "with the specific reason"
assert_contains "$SEC" "**Pass Count:** —" "and every count reads as an em-dash, never 0"
AFTER_REST="$(rest_of_report "$R")"
assert_eq "$BEFORE_REST" "$AFTER_REST" "everything outside the anchors is untouched"
ART="$(artifacts_section "$R")"
assert_contains "$ART" "None — no tests ran" "and Artifacts is cleared the same way Execution Results is"

# ── 2. Missing anchors — an older/hand-edited report ─────────────────────────
echo
echo "-- report with no Execution Results anchors --"

R="$WORK/no-anchors"; rm -rf "$R"; mkdir -p "$R/.specclaw/e2e" "$R/app"
printf '# E2E Test Report: X\n\nNo anchors here.\n' > "$R/.specclaw/e2e/e2e-report.md"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "1" "$RC" "refuses to guess where results go"
assert_contains "$OUT" "no Execution Results anchors" "and names the reason"

# ── 3. No report at all ──────────────────────────────────────────────────────
echo
echo "-- no report at all --"

R="$WORK/no-report"; rm -rf "$R"; mkdir -p "$R/.specclaw"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "1" "$RC" "refuses — there is nothing to patch"
assert_contains "$OUT" "no report at" "and names what's missing"

if ! command -v jq >/dev/null 2>&1; then
  echo
  echo "(remaining cases need jq to author run-config.json fixtures — skipped)"
  echo
  echo "=================================================="
  echo "Passed: $PASS   Failed: $FAIL"
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi

# ── 4. A parseable pass — well-known runner summary lines ────────────────────
echo
echo "-- a parseable run, all passing --"

R="$WORK/all-pass"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"5 passed\""}' \
  > "$R/.specclaw/e2e/run-config.json"
BEFORE_REST="$(rest_of_report "$R")"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 on a clean run"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** yes (exit 0)" "records the exit code"
assert_contains "$SEC" "**Pass Count:** 5" "parses the passed count"
assert_contains "$SEC" "**Fail Count:** 0" "defaults fail to 0 when only passed is reported"
assert_contains "$SEC" "**Pass Percentage:** 100%" "computes 100% pass rate"
AFTER_REST="$(rest_of_report "$R")"
assert_eq "$BEFORE_REST" "$AFTER_REST" "still leaves every other section untouched"

# ── 5. Mixed pass/fail/skip, non-zero exit ───────────────────────────────────
echo
echo "-- a parseable run, mixed pass/fail/skip --"

R="$WORK/mixed"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"12 passed\"; echo \"2 failed\"; echo \"1 skipped\"; exit 1"}' \
  > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "a failing suite still exits 0 (the script did its job)"
assert_contains "$OUT" "WARN" "but warns that the suite itself failed"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** yes (exit 1)" "records the suite's own non-zero exit"
assert_contains "$SEC" "**Pass Count:** 12" "parses passed"
assert_contains "$SEC" "**Fail Count:** 2" "parses failed"
assert_contains "$SEC" "**Skipped Count:** 1" "parses skipped"
assert_contains "$SEC" "**Pass Percentage:** 80%" "12/(12+2+1) rounds to 80%"

# ── 6. Mocha-style wording ("passing"/"failing"/"pending") ───────────────────
echo
echo "-- Mocha-style summary wording --"

R="$WORK/mocha"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"  3 passing (10ms)\"; echo \"  1 pending\""}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Pass Count:** 3" "'passing' is recognised as pass"
assert_contains "$SEC" "**Skipped Count:** 1" "'pending' is recognised as skipped"

# ── 7. dotnet-test-style wording ("Passed: N") ────────────────────────────────
echo
echo "-- dotnet-test-style summary wording --"

R="$WORK/dotnet"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"Passed:    9, Failed:     0, Skipped:     1\""}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Pass Count:** 9" "'Passed: N' is recognised"
assert_contains "$SEC" "**Fail Count:** 0" "'Failed: N' is recognised"
assert_contains "$SEC" "**Skipped Count:** 1" "'Skipped: N' is recognised"

# ── 8. Unparseable output — never a fabricated zero ─────────────────────────
echo
echo "-- output this script cannot parse --"

R="$WORK/unparseable"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"all good, nothing structured here\""}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** yes (exit 0)" "still records that it ran"
assert_contains "$SEC" "NOT MEASURED" "but the counts read NOT MEASURED"
assert_not_contains "$SEC" "**Pass Count:** 0" "never a fabricated zero"

# ── 9. A failed install command never runs the tests ────────────────────────
echo
echo "-- a failed install command skips the test command entirely --"

R="$WORK/install-fails"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"exit 3", test_cmd:"touch should-not-run.marker"}' \
  > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 — a failed install is a recorded reason, not a script failure"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** no — install command failed" "the report says install failed"
[ -f "$R/app/should-not-run.marker" ] && bad "the test command never ran" \
  "found should-not-run.marker" || ok "the test command never ran"

# ── 10. Empty test_cmd ───────────────────────────────────────────────────────
echo
echo "-- empty test_cmd --"

R="$WORK/empty-test-cmd"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:""}' \
  > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0"
assert_contains "$OUT" "no test_cmd" "and names the reason"

# ── 11. A service already running is left alone ──────────────────────────────
echo
echo "-- a service already running is never started --"

R="$WORK/svc-already-running"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", services:[
    {name:"postgres", kind:"dependency", start_cmd:"touch should-not-start.marker", check_cmd:"true", ready_timeout_seconds:5, poll_interval_seconds:1}
  ], test_cmd:"echo \"1 passed\""}' > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0"
assert_contains "$OUT" "already running" "says the service was already running"
[ -f "$R/app/should-not-start.marker" ] && bad "the already-running service was never started" \
  "found should-not-start.marker — start_cmd ran anyway" \
  || ok "the already-running service was never started"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Pass Count:** 1" "and the test still ran normally"

# ── 12. Services start in order, each gated on the one before ───────────────
echo
echo "-- services start in declared order, each waited on before the next --"

R="$WORK/svc-order"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", services:[
    {name:"backend-api", kind:"backend",
     start_cmd:"sleep 1; touch backend-ready.marker; sleep 30",
     check_cmd:"test -f backend-ready.marker", ready_timeout_seconds:10, poll_interval_seconds:1},
    {name:"frontend-web", kind:"frontend",
     start_cmd:"test -f backend-ready.marker && (sleep 1; touch frontend-ready.marker; sleep 30)",
     check_cmd:"test -f frontend-ready.marker", ready_timeout_seconds:10, poll_interval_seconds:1}
  ], test_cmd:"test -f backend-ready.marker && test -f frontend-ready.marker && echo \"2 passed\""}' \
  > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0"
assert_contains "$OUT" "'backend-api' is ready" "backend reports ready before frontend starts"
assert_contains "$OUT" "'frontend-web' is ready" "and frontend — whose own start_cmd depends on the backend marker — becomes ready too"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Pass Count:** 2" "the test command sees both services up"

# ── 13. A service that never becomes ready: recorded, never fatal, no leak ──
echo
echo "-- a service that never becomes ready is recorded, and its process is torn down --"

R="$WORK/svc-never-ready"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", services:[
    {name:"backend-api", kind:"backend",
     start_cmd:"echo $$ > backend.pid; sleep 30",
     check_cmd:"test -f backend-ready.marker", ready_timeout_seconds:2, poll_interval_seconds:1}
  ], test_cmd:"touch should-not-run.marker"}' > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 — an unready service is a recorded reason, not a script failure"
SEC="$(exec_section "$R")"
assert_contains "$SEC" "**Executed:** no — service 'backend-api' did not become ready" \
  "the report names the service that never came up"
[ -f "$R/app/should-not-run.marker" ] && bad "the test command never ran" \
  "found should-not-run.marker" || ok "the test command never ran"
SVC_PID="$(cat "$R/app/backend.pid" 2>/dev/null || true)"
if [ -n "$SVC_PID" ]; then
  sleep 1
  if kill -0 "$SVC_PID" 2>/dev/null; then
    bad "the unready service's own process is torn down" "pid $SVC_PID is still alive"
  else
    ok "the unready service's own process is torn down"
  fi
else
  echo "  (skipped — could not capture the service's pid on this platform)"
fi

# ── 14. No artifacts_dir declared ────────────────────────────────────────────
echo
echo "-- no artifacts_dir declared --"

R="$WORK/art-none-declared"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"1 passed\""}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
ART="$(artifacts_section "$R")"
assert_contains "$ART" "None — no artifacts_dir declared" "reads as None with the specific reason"

# ── 15. artifacts_dir declared, nothing written (e.g. a fully-passing run) ───
echo
echo "-- artifacts_dir declared but nothing was written there --"

R="$WORK/art-empty-dir"; new_project "$R"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"3 passed\"", artifacts_dir:"test-results"}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
ART="$(artifacts_section "$R")"
assert_contains "$ART" "None — nothing found in" "reads as None, never fabricates a file"
COPIED_NONE="$(find "$R/.specclaw/e2e/artifacts" -type f 2>/dev/null || true)"
assert_eq "" "$COPIED_NONE" "and copies nothing into .specclaw/e2e/artifacts/"

# ── 16. artifacts_dir declared and populated: copied, typed, and listed ─────
echo
echo "-- captured screenshot + video are copied, typed, and listed in the report --"

R="$WORK/art-populated"; new_project "$R"
mkdir -p "$R/app/test-results/checkout-should-reject-empty-cart"
echo fakepng   > "$R/app/test-results/checkout-should-reject-empty-cart/test-failed-1.png"
echo fakevideo > "$R/app/test-results/checkout-should-reject-empty-cart/video.webm"
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"1 passed\"; echo \"1 failed\"", artifacts_dir:"test-results"}' \
  > "$R/.specclaw/e2e/run-config.json"
BEFORE_REST="$(rest_of_report "$R")"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0"
assert_contains "$OUT" "Captured 2 artifact file(s)" "reports how many files it captured"
ART="$(artifacts_section "$R")"
assert_contains "$ART" "| Screenshot | \`.specclaw/e2e/artifacts/" "the screenshot is listed, typed correctly"
assert_contains "$ART" "test-failed-1.png\` |" "with its filename preserved"
assert_contains "$ART" "| Video | \`.specclaw/e2e/artifacts/" "the video is listed, typed correctly"
assert_contains "$ART" "video.webm\` |" "with its filename preserved"
assert_contains "$ART" "checkout-should-reject-empty-cart/" "the framework's own per-test folder structure is preserved"
COPIED="$(find "$R/.specclaw/e2e/artifacts" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
assert_eq "2" "$COPIED" "both files actually landed on disk under .specclaw/e2e/artifacts/"
AFTER_REST="$(rest_of_report "$R")"
assert_eq "$BEFORE_REST" "$AFTER_REST" "and every other section of the report is still untouched"

# ── 17. HTML report: verdict banner, donut, stat cards, and tables match ────
echo
echo "-- HTML report: verdict banner, donut chart, stat cards and tables agree with the markdown --"

# A fully custom report (not the raw {{placeholder}} template) so Detection
# Summary / Page Objects / Test Scripts / Gaps have real content to render.
seed_filled_report() {
  local root="$1" title="$2" gaps_block="$3"
  mkdir -p "$root/.specclaw/e2e" "$root/app"
  cp "$TEMPLATE" "$root/.specclaw/e2e/e2e-report.md"
  cat > "$root/.specclaw/e2e/e2e-report.md" <<MDEOF
# E2E Test Report: ${title}

**Path analyzed:** .
**Date generated:** 2026-09-21

## Detection Summary

Platform: **Web (SPA)**. Stack: React, from \`package.json\`.

## Setup / Execution Commands

\`\`\`bash
npm install
npx playwright test
\`\`\`

## Page Objects Generated

| File | Real Surface Encapsulated |
|---|---|
| src/e2e/pages/LoginPage.ts | Login screen |

## Test Scripts Generated

### Module: User Authentication

- Login rejects empty password
  - Shows a validation message when the password field is empty
  - Keeps the submit button disabled
  - Evidence: \`src/validators/login.ts:12\`
  - Test file: \`src/e2e/tests/login.spec.ts\`

### Module: Checkout

- Checkout blocks an empty cart
  - Shows an error when checkout is attempted with zero items
  - Evidence: \`src/components/Cart.tsx:44\`
  - Test file: \`src/e2e/tests/checkout.spec.ts\`

## Execution Results

<!-- e2e-report:execution-results:begin -->
{{execution_results}}
<!-- e2e-report:execution-results:end -->

## Artifacts

<!-- e2e-report:artifacts:begin -->
{{artifacts}}
<!-- e2e-report:artifacts:end -->

## Gaps

${gaps_block}
MDEOF
}

R="$WORK/html-stats"; rm -rf "$R"
seed_filled_report "$R" "Acme Storefront" \
  "- Admin bulk-delete flow: not reachable from the public UI.
- Legacy CSV export: feature flag disabled, cannot be driven through the E2E surface."
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"12 passed\"; echo \"2 failed\"; echo \"1 skipped\""}' \
  > "$R/.specclaw/e2e/run-config.json"
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
HTML="$R/.specclaw/e2e/e2e-report.html"
[ -f "$HTML" ] && ok "e2e-report.html is written" || bad "e2e-report.html is written" "file missing"
H="$(cat "$HTML" 2>/dev/null || true)"
assert_contains "$H" "Acme Storefront" "the title is carried through"
assert_contains "$H" "<div class=\"stat-value stat-total\">15</div>" "Total = Pass + Fail + Skipped (12+2+1)"
assert_contains "$H" "<div class=\"stat-value stat-pass\">12</div>" "Passed matches the markdown's Pass Count"
assert_contains "$H" "<div class=\"stat-value stat-fail\">2</div>" "Failed matches the markdown's Fail Count"
assert_contains "$H" "<div class=\"stat-value stat-gaps\">2</div>" "Gaps counts the two bullet items"
assert_contains "$H" "verdict-banner shadow-sm mb-4 bg-warning text-dark" "a mostly-passing run gets the amber 'Needs Attention' banner"
assert_contains "$H" "12 of 15 checks passed, but 2 failed." "the banner states the result in one plain-English sentence"
assert_contains "$H" "conic-gradient(#198754 0% 80%, #dc3545 80% 93%, #adb5bd 93% 100%)" "the pass-rate donut's slices match the real Pass/Fail/Skipped split"
assert_contains "$H" "<div class=\"fs-4 fw-bold\">80%</div>" "the donut's own centre label matches the Pass Percentage"
assert_contains "$H" "cdn.jsdelivr.net/npm/bootstrap" "styling is pulled from a CDN, not vendored"
assert_contains "$H" "<th>File</th><th>Real Surface Encapsulated</th>" "the Page Objects table survives the transform"
assert_contains "$H" "Admin bulk-delete flow" "gap bullets are listed in the Gaps card, not just counted"
assert_contains "$H" "<details class=\"tech-details" "developer-only content (stack, run commands) sits behind a single collapsible section"
assert_contains "$H" "Technical Details (for developers)" "labelled plainly, so a non-technical reader knows it's optional"
assert_not_contains "$H" "Tests Written" "the old technical-only test table is gone — Test Scenarios is now the one place this content lives"

# The plain-language Test Scenarios list, grouped by module/feature (never by
# raw file path), with the individual checks each script makes nested
# underneath — this is what lets a reader reconcile a test-runner's own
# aggregate pass count against the (smaller) number of named scenarios, and
# it's the thing this whole feature exists for.
assert_contains "$H" "Test Scenarios <span class=\"badge bg-primary\">2 scenario(s) · 7 checks</span>" \
  "the badge shows both the scenario count and the individual-check count"
assert_contains "$H" "module-title\">📦 User Authentication</h3>" "scenarios are grouped under a plain-language module heading"
assert_contains "$H" "module-title\">📦 Checkout</h3>" "one heading per module, not just the first"
assert_contains "$H" "scenario-headline\"><span class=\"scenario-icon\">🎯</span> Login rejects empty password</div>" \
  "the scenario headline is the plain-language summary — no raw file path in it"
assert_not_contains "$H" "scenario-headline\"><span class=\"scenario-icon\">🎯</span> <strong>src/" \
  "confirmed: the file path never leads the headline a non-technical reader sees first"
assert_contains "$H" "<li>Shows a validation message when the password field is empty</li>" \
  "the individual checks under each scenario are listed as sub-bullets, not collapsed into the headline"
assert_contains "$H" "<li class=\"meta-item\">Evidence: <code>src/validators/login.ts:12</code></li>" \
  "the evidence citation is still present, inline code preserved, but styled as de-emphasized metadata"
assert_contains "$H" "<li class=\"meta-item\">Test file: <code>src/e2e/tests/login.spec.ts</code></li>" \
  "the file path itself survives too, just moved out of the headline and into the same de-emphasized metadata line"
SCENARIOS_POS="$(printf '%s' "$H" | grep -bo 'Test Scenarios' | head -1 | cut -d: -f1)"
DETAILS_POS="$(printf '%s' "$H" | grep -bo '<details class="tech-details' | head -1 | cut -d: -f1)"
if [ -n "$SCENARIOS_POS" ] && [ -n "$DETAILS_POS" ] && [ "$SCENARIOS_POS" -lt "$DETAILS_POS" ]; then
  ok "Test Scenarios sits in front of the collapsed Technical Details, not inside it"
else
  bad "Test Scenarios sits in front of the collapsed Technical Details, not inside it" \
    "scenarios at byte ${SCENARIOS_POS:-?}, details at byte ${DETAILS_POS:-?}"
fi

# ── 18. HTML report: not-executed state degrades to placeholders, not errors ─
echo
echo "-- HTML report: a not-executed run shows placeholders and a banner --"

R="$WORK/html-not-executed"; rm -rf "$R"
seed_filled_report "$R" "No Config Yet" "- None — every considered flow was converted to an E2E test."
(cd "$R" && bash "$BIN" run .specclaw) >/dev/null 2>&1
H="$(cat "$R/.specclaw/e2e/e2e-report.html" 2>/dev/null || true)"
assert_contains "$H" "<div class=\"stat-value stat-total\">—</div>" "Total shows an em-dash, never a fabricated 0"
assert_contains "$H" "verdict-banner shadow-sm mb-4 bg-secondary text-white" "a not-executed run gets the neutral grey 'Not Run Yet' banner"
assert_contains "$H" "Not Run Yet" "with a plain-English headline, not just a technical field"
assert_contains "$H" "<div class=\"stat-value stat-gaps\">0</div>" "a lone 'None' gap bullet counts as zero"
assert_contains "$H" "Every flow that was considered could be turned into an automated test." \
  "and the Gaps card shows a friendly all-clear message, not the raw 'None —' bullet"

# ── 19. HTML report never executes or corrupts on hostile agent content ─────
echo
echo "-- HTML report: \$(...), backticks and <script> in agent content are inert --"

R="$WORK/html-injection"; rm -rf "$R"
seed_filled_report "$R" 'Sketchy $(touch INJECTED.marker) `id` <script>alert(1)</script>' \
  "- Uses \$HOME and \`\$(whoami)\` in its own description: must render as text."
jq -n '{working_dir:"app", install_cmd:"", test_cmd:"echo \"1 passed\""}' \
  > "$R/.specclaw/e2e/run-config.json"
OUT="$(cd "$R" && bash "$BIN" run .specclaw 2>&1)"; RC=$?
assert_eq "0" "$RC" "exits 0 even with hostile content in the report"
[ -f "$R/app/INJECTED.marker" ] && bad "the \$(...) in the title is never executed" \
  "found INJECTED.marker — command substitution ran" \
  || ok "the \$(...) in the title is never executed"
H="$(cat "$R/.specclaw/e2e/e2e-report.html" 2>/dev/null || true)"
assert_not_contains "$H" "<script>alert(1)</script>" "a literal <script> tag never survives into the HTML"
assert_contains "$H" "&lt;script&gt;alert(1)&lt;/script&gt;" "it is escaped to inert text instead"
assert_contains "$H" "\$(touch INJECTED.marker)" "the \$(...) text itself is preserved, just not evaluated"

echo
echo "=================================================="
echo "Passed: $PASS   Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
