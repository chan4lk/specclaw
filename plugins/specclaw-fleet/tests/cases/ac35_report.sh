#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/report-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/report-env.sh"
rows=1
want() { local name="$1" filter="$2"; shift 2; local out rc=0; out="$(run --json "$@")" || rc=$?
  (( rc == 0 )) && jq -e "$filter" <<<"$out" >/dev/null 2>&1 || { rows=0; echo "  [$name] rc=$rc $(head -c 400 <<<"$out") $(head -c 200 "$TMP/err")"; }; }
BASE='.version == 1 and .scope == "latest" and ([.rows[].change] == ["002-a", "003-b"])'
A='(.rows[0] | .state == "pr_open" and .pipeline_run == "100" and .queued == "2026-11-09T11:04:00Z" and .agent_s == 1800 and .cost_usd == 2.5 and .review_rounds == 3 and .pr_opened == "2026-11-09T11:40:00Z" and .pr_status == "completed" and .job == "fleet-002-a" and .wave == null)'
B='(.rows[1] | .state == "running" and .phase == "active" and .agent_started == "2026-11-09T12:10:00Z" and .queued == null and .agent_s == null)'
TOT='(.totals | .jobs == 2 and .agent_s == 1800 and .hosted_s == 120 and .review_rounds == 3 and .commits == 7 and .claude_fetch_s == 7 and .cost_usd == 2.5 and .running == 1 and .prs_open == 0 and .unknown == 1 and (.wall_s | type) == "number")'
reset; want "default scope, newest run only, gap fill" "$BASE and $A and $B and $TOT"
for body in EMPTY '<html>' '[]' '"s"' FAIL500; do
  for src in pullrequests-11 builds-100; do
    reset; if [[ "$body" == EMPTY ]]; then api "$src" ''; else api "$src" "$body"; fi
    case "$src" in pullrequests-*) why=pr f='.pr_status == null and .pr_opened == null' t='.prs_open == 0 and .hosted_s == 120' ;; *) why=build f='.queued == null' t='.hosted_s == 0' ;; esac
    want "$src answers [$body]: row kept, marked unread" "$BASE and (.rows[0] | .state == \"pr_open\" and .agent_s == 1800 and .note == \"unread: $why\" and $f) and (.totals | .jobs == 2 and .agent_s == 1800 and $t)"
  done
done
reset; api pullrequests-11 '{"status":"active"} trailing'; want "an object then garbage: the object is read" "$BASE and .rows[0].pr_status == \"active\" and .rows[0].note == null and .totals.prs_open == 1"
reset; echo '{"records":[{"at":"2026-11-08T20:00:00Z","state":"pr_open"},{"at":"2026-11-08T19:00:00Z","state":"dispatched"}]}' > "$WI/004-c"; want "latest build drops runs dispatched >12h before the newest" "$BASE"
for bad in fail junk noarray; do
  reset; case "$bad" in fail) touch "$WI/003-b.fail" ;; junk) echo "<html>" > "$WI/003-b" ;; noarray) echo '{"records":"x"}' > "$WI/003-b" ;; esac
  want "records $bad: a ? row with a note, never dropped" "$BASE and (.rows[1] | .state == \"?\" and (.note | test(\"records\"))) and .totals.running == 0"
  grep -q "003-b: records .*; shown as ?" "$TMP/err" || { rows=0; echo "  [records $bad] no warning"; }
done
reset; echo '{"records":[{"at":5,"state":"dispatched"}]}' > "$WI/003-b"
want "records whose run cannot be merged: a ? row" '[.rows[] | "\(.change)=\(.state)=\(.note)"] == ["003-b=?=records unparsable"]' --since 2026-11-09T12:00:00Z
for junk in fail empty html items itemjunk; do
  reset; if [[ $junk == fail ]]; then export KUBE_FAIL=1; else export KUBE_JUNK=$junk; fi
  want "cluster answer $junk: live row keeps its state, marked unread" "$BASE and (.rows[1] | .state == \"running\" and .note == \"unread: build, cluster\") and .totals.running == 1"
  unset KUBE_FAIL KUBE_JUNK
done
reset; echo '{"records":[{"at":"2026-11-09T12:20:00Z","state":"pr_open","agent_started":5},{"at":"2026-11-09T12:05:00Z","state":"dispatched"}]}' > "$WI/003-b"
want "a record shape that breaks the row (no cluster read): a ? row" "$BASE and .rows[1].state == \"?\" and .rows[1].note == \"row could not be built\""
for ph in failed:failed complete:stalled gone:stalled; do
  reset; KUBE_PHASE=${ph%%:*} want "Job ${ph%%:*} while records say running: ${ph#*:}, not live" "$BASE and (.rows[1] | .state == \"${ph#*:}\" and (.exit | test(\"no outcome\"))) and .totals.running == 0"
done
reset; sed -i.b 's/"pipeline_run":"101"/"pipeline_run":"100"/' "$WI/003-b"; want "two rows from one pipeline run count its hosted time once" ".totals.hosted_s == 120 and .totals.unknown == 0"
reset; touch "$WI/003-b.fail"; want "an unreadable row counts as unknown" ".totals.unknown == 1 and .totals.running == 0"
reset; want "a run missing cost or commits makes those totals partial" '.totals.partial == ["agent_commits", "agent_s", "cost_usd", "review_rounds"]'
reset; want "--since drops older runs" '[.rows[].change] == ["003-b"]' --since 2026-11-09T12:00:00Z
reset; want "--feature attaches waves" '.scope == "feature:cat" and ([.rows[] | "\(.change)=\(.wave)"] == ["002-a=1", "003-b=2"])' --feature cat
reset; want "named change without records still gets a row" '[.rows[] | "\(.change)=\(.state)"] == ["004-c=null", "002-a=pr_open"]' 004-c 002-a
reset; ( run --since yesterday >/dev/null ) && { rows=0; echo "  bad --since accepted"; }
json_ok() { (( rows == 1 )); }
check "R054 AC-2 report --json: newest run per change, PR/build/cluster gap fill, totals; a failed, empty or garbled PR, build or cluster answer keeps the row and marks it unread (exit 0); a failed, finished or vanished Job ends a live row; unknown rows are counted; totals missing a running row's value are marked partial; a shared pipeline run counts once; unreadable records give a ? row and a warning, never a dropped row; --since, --feature, named scopes; bad --since refused" json_ok
finish
