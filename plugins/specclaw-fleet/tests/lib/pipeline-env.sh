# shellcheck shell=bash disable=SC2034
export TMP AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/ FLEET_REF=refs/heads/main
APPROVED='{"phase":"proposal","phases":{"proposal":{"status":"approved"}}}'
stub specclaw-fleet 'echo "ref=${FLEET_REF:-}" >> "$TMP/refs"; echo "trusted=${FLEET_TRUSTED_CONFIG:-unset} commit=${FLEET_TRUSTED_COMMIT:-unset}" >> "$TMP/trusted"; exit "${DISPATCH_RC:-0}"'
stub git 'case "$1" in fetch) exit "${TRUSTED_FETCH_RC:-0}" ;; show) [[ -n "${TRUSTED_SHOW_FAIL:-}" ]] && exit 128; printf "fleet:\n  vault: trusted-kv\n" ;; rev-parse) [[ -n "${TRUSTED_REV_EMPTY:-}" ]] || echo 0123abc ;; esac'
python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); print([s for s in d["jobs"][0]["steps"] if s.get("task") == "AzureCLI@2"][0]["inputs"]["inlineScript"], end="")' "$FLEET_ROOT/pipelines/${PIPELINE_FILE:-dispatch.yml}" > "$TMP/step.sh"

run_with_state() {
  rm -rf "$TMP/r" && mkdir -p "$TMP/r/.specclaw/changes/$1"
  printf '%s' "$2" > "$TMP/r/.specclaw/changes/$1/state.json"
  : > "$CALLS"
  (cd "$TMP/r" && bash "$TMP/step.sh") > "$TMP/out" 2>&1
}
