# shellcheck shell=bash disable=SC2034
export AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/
APPROVED='{"phase":"proposal","phases":{"proposal":{"status":"approved"}}}'
stub specclaw-fleet 'exit "${DISPATCH_RC:-0}"'
sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/dispatch.yml" | sed '1d;$d;s/^        //' > "$TMP/step.sh"

run_with_state() {
  rm -rf "$TMP/r" && mkdir -p "$TMP/r/.specclaw/changes/$1"
  printf '%s' "$2" > "$TMP/r/.specclaw/changes/$1/state.json"
  : > "$CALLS"
  (cd "$TMP/r" && bash "$TMP/step.sh") > "$TMP/out" 2>&1
}
