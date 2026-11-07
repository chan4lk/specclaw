# shellcheck shell=bash disable=SC2034
export SPECCLAW_DIR="$TMP/repo/.specclaw" APPLIED="$TMP/applied" CHANGE="049-x"
export WI_JSON='{"fields":{"System.AssignedTo":{"uniqueName":"Alice@Contoso.com"},"System.Tags":"specclaw; fleet:auto"}}'
export JOBS_JSON='{"items":[]}'
CANARY="sk-ant-oat01-DISPATCH-CANARY"
H="$(hash_of alice@contoso.com)"

reset_env() {
  rm -rf "$TMP/repo" "$APPLIED" "$KV"
  mkdir -p "$SPECCLAW_DIR/changes/$CHANGE" "$APPLIED" "$KV"
  git -C "$TMP/repo" init -q && git -C "$TMP/repo" remote add origin https://user:pat@dev.azure.com/o/p/_git/r
  printf 'fleet:\n  vault: v\n' > "$SPECCLAW_DIR/config.yaml"
  echo '{"phases":{"proposal":{"status":"approved"}}}' > "$SPECCLAW_DIR/changes/$CHANGE/state.json"
  printf '**Azure Boards Work Item:** [#42](https://x)\n' > "$SPECCLAW_DIR/changes/$CHANGE/status.md"
  printf '%s' "$CANARY" > "$KV/claude-token-$H"
  printf '%s' "$CANARY" > "$KV/codex-auth-$H"
  : > "$CALLS"
}

stub_cluster() {
  stub_az
  stub specclaw-azdo-issue '[[ "$1" == show ]] && echo "$WI_JSON"; exit 0'
  stub kubectl '
case "$*" in
  *" apply -f -") cat > "$APPLIED/$(find "$APPLIED" -type f | wc -l | tr -d " ").yaml" ;;
  *"agent=codex,"*) echo "$JOBS_JSON" ;;
  *"specclaw.fleet/change="*) echo job.batch/fleet-049-a ;;
  *" get job "*) echo uid-1 ;;
  *"current-context"*) echo k3s-a ;;
esac'
}

dispatch() {
  "$FLEET" dispatch "$CHANGE" "$@" > "$TMP/out" 2>&1
}

nothing_applied() { [[ -z "$(ls -A "$APPLIED")" ]] && ! grep -q "kubectl.* apply" "$CALLS"; }
marked_failed() { grep -q "specclaw-azdo-issue fields .*state=failed" "$CALLS"; }
