#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
export AZDO_ORG=o AZDO_PROJECT=p FLEET_REMOTE=local
https_local_remote
publish() {
  rm -rf "$TMP/remote.git" && git init -q --bare "$TMP/remote.git"
  git -C "$TMP/repo" remote remove local 2>/dev/null; git -C "$TMP/repo" remote add local "$TMP/remote.git"
  git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m s && git -C "$TMP/repo" push -q local HEAD:main
}
OTHER='{"value":[{"revisedBy":{"uniqueName":"m@c.com"},"fields":{"System.Tags":{"newValue":"fleet:auto"}}}]}'
agree=1
row() {
  local label="$1" mode="$2"; shift 2
  reset_env; prep; publish; env "$@" "$FLEET" dispatch "$CHANGE" > "$TMP/d.out" 2>&1; d=$?
  reset_env; prep; publish; env "$@" "$FLEET" trigger "$CHANGE" > "$TMP/t.out" 2>&1; t=$?
  local quiet=1; grep -qE "azdo-issue (fields|tag|untag|claim|create)|pipelines run" "$CALLS" && quiet=0
  stem() { sed -E 's/ \(remove the fleet:refused tag to retry\)//; s/^ERROR: //' "$1" | grep -m1 "$CHANGE"; }
  if (( d != t || quiet == 0 )) || { [[ "$mode" == same ]] && [[ "$(stem "$TMP/d.out")" != "$(stem "$TMP/t.out")" ]]; }; then
    agree=0; echo "  differ on $label: dispatch=$d trigger=$t"
  fi
}
prep() { :; }
row "no tag" same "WI_JSON={\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"a@c.com\"},\"System.Tags\":\"x\"}}"
row "no assignee" same 'WI_JSON={"fields":{"System.Tags":"fleet:auto"}}'
row "other tagger" same "WI_UPDATES=$OTHER"
row "history unreadable" same WI_UPDATES=FAIL
row "handled" same 'WI_JSON={"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"fleet:auto; fleet:dispatched"}}'
row "vault unreadable" same AZ_FAIL=1
prep() { rm -f "$KV/claude-token-$H"; }; row "credential missing" same X=1
prep() { seed_codex_job '{"active":1}'; }; row "codex busy" same FLEET_DEFAULT_AGENT=codex
prep() { : > "$SPECCLAW_DIR/changes/$CHANGE/status.md"; }; row "no work item" codes X=1
prep() { echo '{"phases":{"proposal":{"status":"draft"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"; }; row "unapproved" codes X=1
reset_env; publish; FLEET_NAMESPACE=team-a FLEET_DEFAULT_AGENT=codex "$FLEET" trigger "$CHANGE" > "$TMP/out" 2>&1; ns_calls="$(cat "$CALLS")"
same_ns() { grep -q "kubectl -n team-a --request-timeout=15s get job fleet-codex-$H -o json" <<<"$ns_calls"; }
check "AC8 trigger's busy check reads the same namespace and Job name dispatch uses" same_ns
parity() { (( agree == 1 )); }
check "AC8 trigger and dispatch agree on the verdict for all ten outcomes and the message for the eight shared ones (approval and missing work item word their remedies differently by design); trigger writes nothing" parity
finish
