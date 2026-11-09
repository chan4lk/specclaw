# shellcheck shell=bash
REPORT_RUN='[.records[]? | objects] as $r | ($r | map(.state) | index("dispatched")) as $i
  | if ($r | length) == 0 then null else ($r[0:(($i // (($r | length) - 1)) + 1)] | reverse) as $run
    | ($run | add) + {dispatched_at: $run[0].at, state: $run[-1].state,
        running_at: ([$run[] | select(.state == "running") | .at] | last),
        ended_at: ([$run[] | select(.state | IN("pr_open", "failed")) | .at] | last)}
    | if $since != "" and ((.dispatched_at // "") | sub("\\.[0-9]+"; "")) < $since then null else . end end'

REPORT_ROW='def t: if . == null or . == "" or (tostring | startswith("0001")) then null else sub("\\.[0-9]+"; "") end;
  def n: if . == null or . == "" then null else (tonumber? // null) end;
  def secs(a; b): if a and b then (b | fromdateiso8601) - (a | fromdateiso8601) else null end;
  ($r.agent_started // $r.running_at | t) as $s0 | ($r.agent_ended // $r.ended_at | t) as $s1
  | {change: $c, work_item: (if $id == "" then null else $id end), wave: ($w | n), state: $r.state, exit: $r.exit,
     pipeline_run: $r.pipeline_run, dispatched: ($r.dispatched_at | t),
     queued: ($b.queueTime | t), started: ($b.startTime | t), finished: ($b.finishTime | t),
     job: ($j.job // $r.job), phase: $j.phase, agent_started: $s0, agent_ended: $s1,
     agent_s: (($r.agent_s | n) // secs($s0; $s1)), claude_fetch_s: ($r.claude_fetch_s | n),
     review_rounds: ($r.review_rounds | n), agent_commits: ($r.agent_commits | n),
     cost_usd: ($r.cost_usd | n), turns: ($r.turns | n), model: $r.model,
     pr: (if ($r.pr // "none") == "none" then null else $r.pr end),
     pr_status: $p.status, pr_opened: ($p.creationDate | t), pr_closed: ($p.closedDate | t)}'
