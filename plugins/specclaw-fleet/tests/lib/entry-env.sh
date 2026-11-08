# shellcheck shell=bash disable=SC2034
ENTRY="$FLEET_ROOT/image/entrypoint.sh"
stub specclaw-azdo-issue '[[ -n "${REAL_AZDO:-}" ]] && exec "$REAL_AZDO" "$@"; exit 0'
stub curl 'printf "%s\n" "$*" >> "$TMP/curl.log"
case "$*" in
  *pullrequests*searchCriteria*) [[ -n "${EXISTING_PR:-}" ]] && echo "{\"value\":[{\"pullRequestId\":$EXISTING_PR}]}" || echo "{\"value\":[]}"; exit 0 ;;
  *pullrequests*) [[ -n "${PR_POST_FAIL:-}" ]] && exit 22; cat > "$TMP/pr-body.json"; echo "{\"pullRequestId\":77}"; exit 0 ;;
  *--noproxy*) [[ "${GATE:-}" == direct-open ]] && exit 0; exit 7 ;;
  *" -x "*) [[ "${GATE:-}" == proxy-down ]] && exit 7; exit 0 ;;
esac
echo "{}"'
stub git '[[ "$1" == -C && "$3" == merge-base ]] && { [[ -z "${NOT_ANCESTOR:-}" ]]; exit; }
[[ "$1" == -C && "$3" == rev-parse && "$4" == --abbrev-ref ]] && { echo "${ON_BRANCH-specclaw/049-x}"; exit 0; }
[[ "$1" == -C && "$3" == rev-parse ]] && { echo deadbeef; exit 0; }
[[ "$1" == -C && "$3" == ls-remote ]] && { [[ -n "${REMOTE_BRANCH:-}" ]] && printf "abc\trefs/heads/%s\n" "$REMOTE_BRANCH"; exit 0; }
[[ "$1" == clone ]] || exit 0
[[ -n "${CLONE_FAIL:-}" ]] && exit 128
dest="${*: -1}"; mkdir -p "$dest/.specclaw/changes/049-x"
status=approved; [[ -n "${NOT_APPROVED:-}" ]] && status=draft
pr=""; [[ -n "${FAKE_PR:-}" ]] && pr=",\"pr\":{\"url\":\"https://pr/1\"}"
content="{\"branch\":\"specclaw/049-x\",\"phases\":{\"proposal\":{\"status\":\"$status\"}$pr}}"
[[ -n "${STATE_OVERRIDE+x}" ]] && content="$STATE_OVERRIDE"
[[ "$content" == MISSING ]] || printf "%s" "$content" > "$dest/.specclaw/changes/049-x/state.json"
exit 0'
stub claude 'env | grep -E "^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|CODEX_API_KEY)=" >> "$TMP/leaked"
[[ "$CLAUDE_CODE_OAUTH_TOKEN" == oat-token ]] || echo "bad token" >> "$TMP/leaked"
echo "agent says hi; leaked sk-ant-oat01-SECRETTOKENVALUE and pat abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"
sleep "${AGENT_SLEEP:-0}"
exit "${AGENT_RC:-0}"'
export TMP REAL_AZDO=""

run_entry() {
  rm -rf "${TMP:?}/status" "${TMP:?}/work" "${TMP:?}/home"
  mkdir -p "$TMP/status" "$TMP/work" "$TMP/home" "$TMP/seed"
  : > "$CALLS"
  printf 'oat-token' > "$TMP/cred"
  env FLEET_STATUS_DIR="$TMP/status" FLEET_WORK="$TMP/work" FLEET_CRED="$TMP/cred" FLEET_SEED="$TMP/seed" \
    HTTPS_PROXY=http://proxy:3128 FLEET_GATE_TRIES=2 FLEET_GATE_SLEEP=0 AZDO_ORG=o AZDO_PROJECT=p FLEET_WORK_ITEM=42 FLEET_COMMIT=abc123 FLEET_CODEX_HOME="$TMP/codex" FLEET_AZDO_CONFIG=$'azdo:\n  fleet_states:\n    failed: Failed' HOME="$TMP/home" FLEET_AGENT=claude FLEET_CHANGE=049-x FLEET_REF=main AZDO_TOKEN=pat-secret \
    FLEET_REPO_URL=https://dev.azure.com/o/p/_git/r ANTHROPIC_API_KEY=k ANTHROPIC_AUTH_TOKEN=k OPENAI_API_KEY=k CODEX_API_KEY=k \
    bash "$ENTRY" > "$TMP/out" 2>&1
}
