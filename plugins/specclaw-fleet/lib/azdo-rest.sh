# shellcheck shell=bash
azdo_rest() {
  [[ -n "${AZDO_TOKEN:-}" && -n "${AZDO_ORG:-}" && -n "${AZDO_PROJECT:-}" ]] || return 2
  local out code
  out="$(curl -s -m 15 -w '\n%{http_code}' -H "Authorization: Basic $(printf ':%s' "$AZDO_TOKEN" | base64 | tr -d '\n')" \
    "https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/$1")" || return 1
  code="${out##*$'\n'}"
  case "$code" in 2??) printf '%s' "${out%$'\n'*}" ;; 401|403) return 3 ;; *) return 1 ;; esac
}

azdo_pipeline_id() {
  local out
  out="$(azdo_rest "build/definitions?name=$(jq -rn --arg v "$1" '$v|@uri')&api-version=7.1")" || return $?
  jq -er '.value | if type == "array" then (.[0].id // "") else error("no list") end' <<<"$out"
}
