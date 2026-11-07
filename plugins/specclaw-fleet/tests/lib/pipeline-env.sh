# shellcheck shell=bash disable=SC2034
REAL_GIT="$(command -v git)"
export AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/ REAL_GIT SYSTEM_ACCESSTOKEN=t
export SYSTEM_TEAMPROJECTID=p SYSTEM_DEFINITIONID=7 BUILD_SOURCEBRANCH=refs/heads/main BUILDS_JSON='{"value":[]}'
stub curl '[[ -n "${CURL_FAIL:-}" ]] && exit 22; echo "$BUILDS_JSON"'
OK='{"phases":{"proposal":{"status":"approved"}}}'
DRAFT='{"phases":{"proposal":{"status":"draft"}}}'
stub specclaw-fleet 'exit 0'
sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/dispatch.yml" | sed '1d;$d;s/^        //' \
  | sed 's/\${{ parameters.vault }}/kv/' > "$TMP/step.sh"

new_repo() {
  rm -rf "$TMP/r" && mkdir -p "$TMP/r/.specclaw/changes/049-x" && git -C "$TMP/r" init -q
  ln -s .specclaw/changes/049-x "$TMP/r/s"
}

put_state() {
  if [[ "$1" == - ]]; then rm -f "$TMP/r/s/state.json"; else printf '%s' "$1" > "$TMP/r/s/state.json"; fi
  git -C "$TMP/r" add -A && git -C "$TMP/r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m step
}

run_step() {
  : > "$CALLS"
  (cd "$TMP/r" && bash "$TMP/step.sh") > "$TMP/out" 2>&1
}

dispatched() { grep -q "specclaw-fleet dispatch 049-x --vault kv" "$CALLS"; }
