# shellcheck shell=bash disable=SC2034
export FLEET_VAULT=v SPECCLAW_DIR="$TMP/repo/.specclaw" APPLIED="$TMP/applied" CLAIMS="$TMP/claims" CHANGE="049-x"
export WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"specclaw; fleet:auto"}}'
export WI_UPDATES='{"value":[{"revisedBy":{"uniqueName":"alice@contoso.com"},"fields":{"System.Tags":{"oldValue":"specclaw","newValue":"specclaw; Fleet:Auto"}}}]}'
CANARY="sk-ant-oat01-DISPATCH-CANARY"
H="$(hash_of alice@contoso.com)"

reset_env() {
  rm -rf "$TMP/repo" "$APPLIED" "$KV" "$CLAIMS"
  mkdir -p "$SPECCLAW_DIR/changes/$CHANGE" "$APPLIED" "$KV" "$CLAIMS"
  git -C "$TMP/repo" init -q && git -C "$TMP/repo" remote add origin https://user:pat@dev.azure.com/o/p/_git/r
  git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
  printf 'azdo:\n  fleet_states:\n    failed: Failed\n' > "$SPECCLAW_DIR/config.yaml"
  echo '{"phases":{"proposal":{"status":"approved"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"
  printf '**Azure Boards Work Item:** [#42](https://x)\n' > "$SPECCLAW_DIR/changes/$CHANGE/status.md"
  printf '%s' "$CANARY" > "$KV/claude-token-$H"
  printf '%s' "$CANARY" > "$KV/codex-auth-$H"
  : > "$CALLS"
}

stub_cluster() {
  stub_az
  stub specclaw-azdo-issue '
case "$1" in
  show) echo "$WI_JSON" ;;
  updates) [[ "$WI_UPDATES" == FAIL ]] && exit 1; echo "$WI_UPDATES" ;;
  claim) [[ -n "${CLAIM_FAIL:-}" ]] && { echo "ERROR: ADO read failed" >&2; exit 1; }
    mkdir "$CLAIMS/wi-$3" 2>/dev/null || exit 3 ;;
  untag) [[ -n "${UNTAG_FAIL:-}" ]] && exit 1; [[ "$4" == fleet:dispatched ]] && rm -rf "$CLAIMS/wi-$3" ;;
esac
exit 0'
  stub kubectl '
claim="$CLAIMS/claim-$5"
case "$*" in
  *" create -f -")
    doc="$(cat)"; name="$(grep -m1 "^  name: " <<<"$doc" | sed "s/^  name: //")"
    [[ -n "${CREATE_ERR:-}" ]] && grep -q "^kind: ${CREATE_KIND:-Job}" <<<"$doc" && { echo "$CREATE_ERR" >&2; exit 1; }
    mkdir "$CLAIMS/claim-$name" 2>/dev/null || { echo "Error from server (AlreadyExists): $name" >&2; exit 1; }
    echo "uid-$$-$RANDOM" > "$CLAIMS/claim-$name/uid"; echo "{\"active\":1}" > "$CLAIMS/claim-$name/status"
    printf "%s\\n" "$doc" > "$APPLIED/$(date +%s)-$name.yaml" ;;
  "delete --raw "*)
    [[ -n "${DELETE_ERR:-}" ]] && { echo "$DELETE_ERR" >&2; exit 1; }
    claim="$CLAIMS/claim-${3##*/}"
    [[ -n "${SWAP_BEFORE_DELETE:-}" ]] && { echo new-uid > "$claim/uid"; echo "{\"active\":1}" > "$claim/status"; }
    [[ -f "$claim/uid" && "$(cat "$claim/uid")" == "$(jq -r .preconditions.uid "$5")" ]] \
      || { echo "Error from server (Conflict): Precondition failed: UID in precondition" >&2; exit 1; }
    rm -rf "$claim" ;;
  *" get job "*" -o json") [[ -n "${GET_ERR:-}" ]] && { echo "$GET_ERR" >&2; exit 1; }
    [[ -d "$claim" ]] || { echo "Error from server (NotFound): jobs $5" >&2; exit 1; }
    jq -n --arg u "$(cat "$claim/uid")" --argjson s "$(cat "$claim/status")" "{metadata: {uid: \$u}, status: \$s}" ;;
  *" delete job "*) rm -rf "$claim" ;;
  *"specclaw.fleet/change="*) echo job.batch/fleet-049-a ;;
  *" get job "*) cat "$claim/uid" ;;
  *"current-context"*) echo k3s-a ;;
esac'
}

seed_codex_job() {
  mkdir -p "$CLAIMS/claim-fleet-codex-$H"
  echo old-uid > "$CLAIMS/claim-fleet-codex-$H/uid"
  echo "$1" > "$CLAIMS/claim-fleet-codex-$H/status"
}

dispatch() {
  "$FLEET" dispatch "$CHANGE" "$@" > "$TMP/out" 2>&1
}

nothing_applied() { [[ -z "$(ls -A "$APPLIED")" ]] && ! grep -q "kubectl.* create -f" "$CALLS"; }
add_change() {
  mkdir -p "$SPECCLAW_DIR/changes/$1"
  cp "$SPECCLAW_DIR/changes/$CHANGE/state.json" "$SPECCLAW_DIR/changes/$CHANGE/status.md" "$SPECCLAW_DIR/changes/$1/"
}

marked_failed() { grep -q "specclaw-azdo-issue fields .*state=failed" "$CALLS" && grep -q "specclaw-azdo-issue tag .* fleet:refused" "$CALLS"; }
