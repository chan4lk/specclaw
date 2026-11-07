#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
export AZDO_ORG=o AZDO_PROJECT=p FLEET_REMOTE=local
publish() {
  rm -rf "$TMP/remote.git" && git init -q --bare "$TMP/remote.git"
  git -C "$TMP/repo" remote remove local 2>/dev/null; git -C "$TMP/repo" remote add local "$TMP/remote.git"
  git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m s && git -C "$TMP/repo" push -q local HEAD:main
}
OTHER='{"value":[{"revisedBy":{"uniqueName":"m@c.com"},"fields":{"System.Tags":{"newValue":"fleet:auto"}}}]}'
agree=1
for row in "no tag|WI_JSON={\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"a@c.com\"},\"System.Tags\":\"x\"}}" \
           "no assignee|WI_JSON={\"fields\":{\"System.Tags\":\"fleet:auto\"}}" "other tagger|WI_UPDATES=$OTHER" \
           "history unreadable|WI_UPDATES=FAIL" "handled|WI_JSON={\"fields\":{\"System.AssignedTo\":{\"uniqueName\":\"Alice@Contoso.com\"},\"System.Tags\":\"fleet:auto; fleet:dispatched\"}}"; do
  label="${row%%|*}" setting="${row#*|}"
  reset_env; publish; env "$setting" "$FLEET" dispatch "$CHANGE" > "$TMP/d.out" 2>&1; d=$?
  reset_env; publish; env "$setting" "$FLEET" trigger "$CHANGE" > "$TMP/t.out" 2>&1; t=$?
  t_quiet=1; grep -qE "azdo-issue (fields|tag|claim)|pipelines run" "$CALLS" && t_quiet=0
  stem() { sed -E 's/ \(remove the fleet:refused tag to retry\)//; s/^ERROR: //' "$1" | grep -m1 "$CHANGE"; }
  if (( d != t || t_quiet == 0 )) || [[ "$(stem "$TMP/d.out")" != "$(stem "$TMP/t.out")" ]]; then agree=0; echo "  differ on $label: dispatch=$d trigger=$t"; fi
done
parity() { (( agree == 1 )); }
check "AC8 trigger and dispatch give the same verdict and message on every gate; trigger writes nothing" parity
finish
