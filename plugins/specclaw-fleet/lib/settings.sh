# shellcheck shell=bash
FLEET_SETTING_KEYS="vault kube_context kubeconfig cluster_name namespace image claude_version default_agent deadline_minutes pipeline pipeline_file remote ref image_pull_secret node_label"
FLEET_LOCAL_KEYS="kube_context kubeconfig"

setting_var() {
  [[ "$1" == kubeconfig ]] && { printf KUBECONFIG; return; }
  printf 'FLEET_%s' "$(tr '[:lower:]' '[:upper:]' <<<"$1")"
}

looks_secret() {
  [[ "$1" =~ ^sk- || "$1" =~ eyJ[A-Za-z0-9_-]{10,} ]] && return 0
  [[ "$1" == *@sha256:* ]] && return 1
  if [[ "$1" == */* && "$1" =~ ^[^[:space:]]+$ && "$1" =~ [.-] ]]; then
    local seg; local -a segs; IFS=/ read -ra segs <<<"$1"
    for seg in "${segs[@]}"; do [[ "$seg" =~ [A-Za-z0-9+_-]{52,} ]] && return 0; done
    return 1
  fi
  [[ "$1" =~ [A-Za-z0-9+/_-]{52,} ]]
}

fleet_config_lines() {
  awk '/^fleet:[[:space:]]*(#.*)?$/ { on = 1; next } on && /^[^[:space:]#]/ { exit } on { print }' "$1"
}

load_fleet_settings() {
  local cfg="$SPECCLAW_DIR/config.yaml" line key value var indent=""
  [[ -r "$cfg" ]] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^([[:space:]]+)([a-z_]+):[[:space:]]*(.*)$ ]] || continue
    indent="${indent:-${BASH_REMATCH[1]}}"
    [[ "${BASH_REMATCH[1]}" == "$indent" ]] || { warn "ignored nested key ${BASH_REMATCH[2]} under fleet: in $cfg"; continue; }
    key="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    if [[ "$value" =~ ^\"([^\"]*)\" || "$value" =~ ^\'([^\']*)\' ]]; then value="${BASH_REMATCH[1]}"
    else value="${value%%[[:space:]]#*}"; value="${value%"${value##*[![:space:]]}"}"; fi
    [[ " $FLEET_SETTING_KEYS " == *" $key "* ]] || { warn "ignored unknown fleet.$key in $cfg"; continue; }
    looks_secret "$value" && die "fleet.$key in $cfg looks like a secret; keep secrets in .specclaw/.env or Key Vault"
    [[ -n "${TF_BUILD:-}" && " $FLEET_LOCAL_KEYS " == *" $key "* ]] && continue
    var="$(setting_var "$key")"
    [[ -z "${!var+x}" && -n "$value" ]] && { export "$var=$value"; FLEET_CONFIG_VARS+=" $var"; }
  done < <(fleet_config_lines "$cfg")
  return 0
}

reload_fleet_settings() {
  local var
  for var in ${FLEET_CONFIG_VARS:-}; do [[ "$var" == FLEET_REMOTE || "$var" == FLEET_REF ]] || unset "$var"; done
  FLEET_CONFIG_VARS=""
  load_fleet_settings
}
