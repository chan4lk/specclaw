#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/report-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/report-env.sh"
writes=1
for w in dirfile mvdir html; do
  reset; mkdir -p "$SPECCLAW_DIR"; args=(--save)
  case "$w" in dirfile) echo x > "$SPECCLAW_DIR/fleet" ;; mvdir) mkdir -p "$SPECCLAW_DIR/fleet/report.json/x" ;; html) args=(--html "$TMP/no/such/dir/r.html") ;; esac
  out="$(run "${args[@]}")" && { writes=0; echo "  [write $w] exited 0"; }
  grep -qE "saved|wrote" <<<"$out" && { writes=0; echo "  [write $w] claimed success"; }
  grep -q "ERROR: could not" "$TMP/err" || { writes=0; echo "  [write $w] no error"; }
done
writes_ok() { (( writes == 1 )); }
reset; table="$(run)"; html="$TMP/r.html"; run --html "$html" --save >/dev/null
table_ok() { grep -q "^CHANGE " <<<"$table" && grep -q "^002-a .*pr_open .*30m .*#11 completed" <<<"$table" && grep -q "API-equivalent estimate" <<<"$table" && grep -q "1 running · 0 PRs open · 1 unknown · cost \$2.50" <<<"$table"; }
data_safe() { local d; d="$(sed -n 's#^<script id="data" type="application/json">\(.*\)</script>$#\1#p' "$html")"; [[ "$d" == *'\u003c/script>\u003c!--'* && "$d" != *'<'* ]]; }
html_ok() {
  [[ -s "$html" ]] && ! grep -q "__FLEET_REPORT__" "$html" && data_safe \
    && [[ -z "$(grep -oE "https?://[^\"' <]+" "$html" | grep -v '^https://x/pullrequest/11$')" ]] && grep -q '"rows":\[' "$html"
}
save_ok() { jq -e '.version == 1 and (.rows | length) == 2' "$SPECCLAW_DIR/fleet/report.json" >/dev/null && [[ "$(cat "$SPECCLAW_DIR/fleet/.gitignore")" == "*" ]]; }
check "R054 AC-3 report table lists rows and totals with the cost labelled an API-equivalent estimate" table_ok
check "R054 AC-3 report --html is self-contained (no URL but the PR link, every < escaped, data embedded)" html_ok
check "R054 AC-3 report --save writes the v1 snapshot and a folder-local .gitignore" save_ok
check "R054 AC-3 a failed --save (fleet is a file, report.json is a folder) or --html (missing folder) exits non-zero and never claims success" writes_ok
finish
