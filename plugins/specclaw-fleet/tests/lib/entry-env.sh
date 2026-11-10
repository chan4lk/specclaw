# shellcheck shell=bash disable=SC2034
ENTRY="$FLEET_ROOT/image/entrypoint.sh"
# shellcheck source=gpg-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/gpg-env.sh"
make_release "#!/bin/sh"
stub specclaw-azdo-issue '[[ -n "${REAL_AZDO:-}" ]] && exec "$REAL_AZDO" "$@"; exit 0'
stub curl 'printf "%s\n" "$*" >> "$TMP/curl.log"
case "$*" in
  *releases.test/*) out=""; prev=""; for arg in "$@"; do [[ "$prev" == -o ]] && out="$arg"; prev="$arg"; done
    url="${*: -1}"; src="$TMP/releases/${url#https://releases.test/}"; [[ -f "$src" ]] || exit 22; cp "$src" "$out"; exit 0 ;;
  *pullrequests*searchCriteria*) [[ -n "${SEARCH_JUNK+x}" ]] && { printf "%s" "$SEARCH_JUNK"; exit 0; }; [[ -n "${EXISTING_PR:-}" ]] && echo "{\"value\":[{\"pullRequestId\":$EXISTING_PR,\"isDraft\":${EXISTING_DRAFT:-false}}]}" || echo "{\"value\":[]}"; exit 0 ;;
  *"-X PATCH"*pullrequests/*) echo "PATCH $*" >> "$TMP/pr-patch.log"; echo "{}"; exit 0 ;;
  *pullrequests*) [[ -n "${PR_POST_FAIL:-}" ]] && exit 22; cat > "$TMP/pr-body.json"; echo "{\"pullRequestId\":77}"; exit 0 ;;
  *--noproxy*) [[ "${GATE:-}" == direct-open ]] && exit 0; exit 7 ;;
  *" -x "*) [[ "${GATE:-}" == proxy-down ]] && exit 7; exit 0 ;;
esac
echo "{}"'
stub git '[[ "$1" == -C && "$3" == merge-base ]] && { [[ -z "${NOT_ANCESTOR:-}" ]]; exit; }
[[ "$1" == -C && "$3" == rev-parse && "$4" == --abbrev-ref ]] && { [[ -s "$TMP/onbranch" ]] && { cat "$TMP/onbranch"; exit 0; }; echo "${ON_BRANCH-specclaw/049-x}"; exit 0; }
[[ "$1" == -C && "$3" == rev-parse ]] && { echo deadbeef; exit 0; }
[[ "$1" == -C && "$3" == rev-list ]] && { echo "${REVLIST-3}"; exit 0; }
[[ "$1" == -C && "$3" == ls-remote && -n "${LS_FAIL:-}" ]] && exit 128
[[ "$1" == -C && "$3" == fetch && -n "${FETCH_FAIL:-}" ]] && exit 128
[[ "$1" == -C && "$3" == merge ]] && { [[ -n "${MERGE_CONFLICT:-}${MERGE_BROKEN:-}" ]] && exit 1; [[ -n "${MERGE_BRINGS_PASS:-}" ]] && echo pass > "$2/.specclaw/features/049-x/integration-result"; exit 0; }
[[ "$1" == -C && "$3" == diff ]] && { [[ -n "${MERGE_CONFLICT:-}" ]] && echo src/a.ts; exit 0; }
[[ "$1" == -C && "$3" == checkout && "$5" == -b ]] && { echo "$6" > "$TMP/onbranch"; exit 0; }
[[ "$1" == -C && "$3" == ls-remote ]] && { [[ -n "${REMOTE_BRANCH:-}" ]] && printf "abc\trefs/heads/%s\n" "$REMOTE_BRANCH"; exit 0; }
[[ "$1" == clone ]] || exit 0
[[ -n "${CLONE_FAIL:-}" ]] && exit 128
dest="${*: -1}"; kind=changes; [[ "${FLEET_MODE:-}" == integrate ]] && kind=features; mkdir -p "$dest/.specclaw/changes/049-x" "$dest/.specclaw/$kind/049-x"
[[ -n "${PRE_ROUNDS:-}" ]] && { mkdir -p "$dest/.specclaw/changes/049-x/review"; for ((i = 1; i <= PRE_ROUNDS; i++)); do echo "{}" > "$dest/.specclaw/changes/049-x/review/round-p$i.json"; done; }
[[ -n "${CONFIG_PREFIX:-}" ]] && printf "git:\n  branch_prefix: \"%s\"   # p\n" "$CONFIG_PREFIX" > "$dest/.specclaw/config.yaml"
[[ -n "${BASE_BRANCH:-}" ]] && printf "git:\n  base_branch: \"%s\"   # b\n" "$BASE_BRANCH" > "$dest/.specclaw/config.yaml"
[[ -n "${CONFIG_RAW:-}" ]] && printf "%b" "$CONFIG_RAW" > "$dest/.specclaw/config.yaml"
status=approved; [[ -n "${NOT_APPROVED:-}" ]] && status=draft
pr=""; [[ -n "${FAKE_PR:-}" ]] && pr=",\"pr\":{\"url\":\"https://pr/1\"}"
content="{\"branch\":\"specclaw/049-x\",\"phases\":{\"proposal\":{\"status\":\"$status\"}$pr}}"
[[ "$kind" == features ]] && content="{\"kind\":\"feature\",\"phases\":{\"proposal\":{\"status\":\"$status\"}}}"
[[ -n "${STATE_OVERRIDE+x}" ]] && content="$STATE_OVERRIDE"
[[ "$content" == MISSING ]] || printf "%s" "$content" > "$dest/.specclaw/$kind/049-x/state.json"
[[ "$kind" == features ]] && rm -f "$dest/.specclaw/changes/049-x/state.json"
[[ -n "${INTEGRATION_RESULT:-}" ]] && printf "%s\n" "$INTEGRATION_RESULT" > "$dest/.specclaw/features/049-x/integration-result"
exit 0'
stub claude 'echo "${SPECCLAW_PR_TARGET-unset}" > "$TMP/prtarget"
[[ -n "${AGENT_RESULT:-}" ]] && printf "%s\n" "$AGENT_RESULT" > ".specclaw/features/049-x/integration-result"
env | grep -E "^(ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|OPENAI_API_KEY|CODEX_API_KEY)=" >> "$TMP/leaked"
[[ "$CLAUDE_CODE_OAUTH_TOKEN" == oat-token ]] || echo "bad token" >> "$TMP/leaked"
[[ -n "${ROUNDS:-}" ]] && { mkdir -p .specclaw/changes/049-x/review; for ((i = 1; i <= ROUNDS; i++)); do echo "{}" > ".specclaw/changes/049-x/review/round-a$i.json"; done; }
[[ -n "${AGENT_JSON:-}" ]] && printf "%b\n" "$AGENT_JSON"
echo "agent says hi; leaked sk-ant-oat01-SECRETTOKENVALUE and pat abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"
sleep "${AGENT_SLEEP:-0}"
exit "${AGENT_RC:-0}"'
stub codex 'sleep "${AGENT_SLEEP:-0}"; exit "${AGENT_RC:-0}"'
export TMP REAL_AZDO=""

run_entry() {
  rm -rf "${TMP:?}/status" "${TMP:?}/work" "${TMP:?}/home" "${TMP:?}/onbranch"
  mkdir -p "$TMP/status" "$TMP/work" "$TMP/home" "$TMP/seed"
  : > "$CALLS"
  printf 'oat-token' > "$TMP/cred"
  env FLEET_STATUS_DIR="$TMP/status" FLEET_WORK="$TMP/work" FLEET_CRED="$TMP/cred" FLEET_SEED="$TMP/seed" \
    HTTPS_PROXY=http://proxy:3128 FLEET_GATE_TRIES=2 FLEET_GATE_SLEEP=0 AZDO_ORG=o AZDO_PROJECT=p FLEET_WORK_ITEM=42 FLEET_COMMIT=abc123 FLEET_CODEX_HOME="$TMP/codex" FLEET_AZDO_CONFIG=$'azdo:\n  fleet_states:\n    failed: Failed' HOME="$TMP/home" FLEET_AGENT="${ENTRY_AGENT:-claude}" FLEET_CHANGE=049-x FLEET_REF="${ENTRY_REF:-main}" FLEET_PR_TARGET="${ENTRY_PR_TARGET:-}" FLEET_MODE="${ENTRY_MODE:-}" FLEET_MERGE_REF="${ENTRY_MERGE:-}" AZDO_TOKEN=pat-secret \
    FLEET_REPO_URL=https://dev.azure.com/o/p/_git/r ANTHROPIC_API_KEY=k ANTHROPIC_AUTH_TOKEN=k OPENAI_API_KEY=k CODEX_API_KEY=k \
    bash "$ENTRY" > "$TMP/out" 2>&1
}
