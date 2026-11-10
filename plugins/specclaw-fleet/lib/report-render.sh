# shellcheck shell=bash
REPORT_TOTALS='def ts: if . then fromdateiso8601 else null end;
  .rows as $rows | (.generated_at | ts) as $now
  | [$rows[] | (.queued // .dispatched) | ts | select(.)] as $starts
  | [$rows[] | if .state | IN("dispatched", "running") then $now else ((.agent_ended // .pr_opened) | ts) end | select(.)] as $ends
  | .totals = {wall_s: (if ($starts | length) > 0 and ($ends | length) > 0 then ($ends | max) - ($starts | min) else null end),
      jobs: ([$rows[] | select(.job)] | length), agent_s: ([$rows[].agent_s | numbers] | add // 0),
      hosted_s: ([$rows[] | select(.started and .finished)] | group_by(.pipeline_run // .change) | map(.[0] | (.finished | ts) - (.started | ts)) | add // 0),
      review_rounds: ([$rows[].review_rounds | numbers] | add // 0), commits: ([$rows[].agent_commits | numbers] | add // 0),
      claude_fetch_s: ([$rows[].claude_fetch_s | numbers] | max), cost_usd: ([$rows[].cost_usd | numbers] | if length == 0 then null else add end),
      running: ([$rows[] | select(.state | IN("dispatched", "running"))] | length), prs_open: ([$rows[] | select(.pr_status == "active")] | length),
      unknown: ([$rows[] | select(.state == "?" or .note != null)] | length),
      partial: ([($rows[] | select(.agent_started) | to_entries[] | select(.key | IN("agent_s", "cost_usd", "review_rounds", "agent_commits")) | select(.value == null) | .key),
        ($rows[] | (.note // "") | if test("build") then "hosted_s" else empty end, if test("pr") then "prs_open" else empty end)] | unique)}'

REPORT_TABLE='def dur: if . == null then "-" else (. / 60 | floor) as $m | if $m >= 60 then "\($m / 60 | floor)h \($m % 60)m" else "\($m)m" end end;
  def v: if . == null then "-" else tostring end; def ge($k): if (.partial // [] | index($k)) then "≥" else "" end;
  (.rows[] | [.change, (.wave | v), (.state | v), (.agent_s | dur), (.review_rounds | v), (.agent_commits | v),
    (if .pr then "#" + (.pr | split("/") | last) + " " + (.pr_status // "?") else "-" end)] | @tsv),
  "", (.totals | "wall \(.wall_s | dur) · \(.jobs) jobs · agent \(ge("agent_s"))\(.agent_s | dur) · hosted \(ge("hosted_s"))\(.hosted_s | dur) · \(ge("review_rounds"))\(.review_rounds) review rounds · \(ge("agent_commits"))\(.commits) commits · claude download \(.claude_fetch_s | v)s",
    "\(.running) running · \(ge("prs_open"))\(.prs_open) PRs open\(if .unknown > 0 then " · \(.unknown) unknown" else "" end) · cost \(if .cost_usd then ge("cost_usd") + "$" + ((.cost_usd * 100 | round) as $c | "\($c / 100 | floor).\($c % 100 | tostring | if length < 2 then "0" + . else . end)") else "-" end) (API-equivalent estimate)")'

report_scope_name() {
  if [[ -n "$R_FEATURE" ]]; then printf 'feature:%s' "$R_FEATURE"
  elif (( ${#R_CHANGES[@]} )); then printf 'changes'
  else printf 'latest'; fi
}

report_html() {
  local tpl json
  tpl="$(cat "$FLEET_ROOT/lib/report.html")" || die "could not read the report template"
  json="$(jq -c . <<<"$1" | sed 's#<#\\u003c#g')"
  { printf '%s%s%s\n' "${tpl%%__FLEET_REPORT__*}" "$json" "${tpl#*__FLEET_REPORT__}" > "$R_HTML"; } 2>/dev/null || die "could not write $R_HTML"
}

report_save() {
  local dir="$SPECCLAW_DIR/fleet"
  { mkdir -p "$dir" && [[ ! -d "$dir/report.json" ]] && printf '*\n' > "$dir/.gitignore" && printf '%s\n' "$1" > "$dir/report.json.tmp" \
    && mv "$dir/report.json.tmp" "$dir/report.json"; } 2>/dev/null || die "could not save $dir/report.json"
}

report_emit() {
  local doc
  doc="$(jq -c --arg g "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg s "$(report_scope_name)" \
    '{version: 1, generated_at: $g, scope: $s, rows: .} | if $s == "latest" then ([.rows[].dispatched | select(.) | fromdateiso8601] | max) as $top
      | .rows |= map(select(.state == "?" or $top == null or ((.dispatched // "") | if . == "" then false else fromdateiso8601 >= $top - 43200 end))) else . end' <<<"$1" | jq -c "$REPORT_TOTALS")"
  if (( R_SAVE )); then report_save "$doc"; fi
  if [[ -n "$R_HTML" ]]; then report_html "$doc"; fi
  if (( R_JSON )); then printf '%s\n' "$doc"; return 0; fi
  jq -r "$REPORT_TABLE" <<<"$doc" | awk -F'\t' 'BEGIN { printf "%-34s %-4s %-10s %-7s %-6s %-7s %s\n", "CHANGE", "WAVE", "STATE", "AGENT", "ROUNDS", "COMMITS", "PR" }
    NF > 1 { printf "%-34s %-4s %-10s %-7s %-6s %-7s %s\n", $1, $2, $3, $4, $5, $6, $7; next } { print }'
  (( R_SAVE )) && echo "saved $SPECCLAW_DIR/fleet/report.json (open /fleet-pane)"
  [[ -z "$R_HTML" ]] || echo "wrote $R_HTML"
  return 0
}
