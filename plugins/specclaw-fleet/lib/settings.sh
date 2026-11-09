# shellcheck shell=bash
FLEET_SETTING_KEYS="vault cluster_name namespace image claude_version default_agent deadline_minutes pipeline pipeline_file remote ref image_pull_secret node_label"
FLEET_SECURE_KEYS="vault image namespace node_label image_pull_secret claude_version deadline_minutes cluster_name"
FLEET_NUMERIC_KEYS="deadline_minutes"

setting_var() {
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

fleet_config_pairs() {
  local line key value indent=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^([[:space:]]+)([a-z_]+):[[:space:]]*(.*)$ ]] || continue
    indent="${indent:-${BASH_REMATCH[1]}}"
    [[ "${BASH_REMATCH[1]}" == "$indent" ]] || { warn "ignored nested key ${BASH_REMATCH[2]} under fleet: in $1"; continue; }
    key="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    if [[ "$value" =~ ^\"([^\"]*)\" || "$value" =~ ^\'([^\']*)\' ]]; then value="${BASH_REMATCH[1]}"
    else value="${value%%[[:space:]]#*}"; value="${value%"${value##*[![:space:]]}"}"; fi
    printf '%s\t%s\n' "$key" "$value"
  done < <(fleet_config_lines "$1")
}

load_fleet_settings() {
  local cfg="$SPECCLAW_DIR/config.yaml" key value var trusted
  [[ -r "$cfg" ]] || return 0
  while IFS=$'\t' read -r key value; do
    case "$key" in kube_context|kubeconfig) warn "ignored fleet.$key in $cfg: which cluster this machine uses is local; set $([[ $key == kubeconfig ]] && echo KUBECONFIG || echo FLEET_KUBE_CONTEXT) in $SPECCLAW_DIR/.env"; continue ;; esac
    [[ " $FLEET_SETTING_KEYS " == *" $key "* ]] || { warn "ignored unknown fleet.$key in $cfg"; continue; }
    looks_secret "$value" && die "fleet.$key in $cfg looks like a secret; keep secrets in .specclaw/.env or Key Vault"
    [[ " $FLEET_NUMERIC_KEYS " != *" $key "* || -z "$value" || "$value" =~ ^[1-9][0-9]{0,4}$ ]] || die "fleet.$key in $cfg must be a whole number"
    if [[ -n "${FLEET_TRUSTED_CONFIG:-}" && " $FLEET_SECURE_KEYS " == *" $key "* ]]; then
      trusted="$(fleet_config_pairs "$FLEET_TRUSTED_CONFIG" | awk -F'\t' -v k="$key" '$1 == k { print $2; exit }')"
      [[ "$value" == "$trusted" ]] || die "fleet.$key on this branch differs from the trusted branch; security settings come only from there"
    fi
    var="$(setting_var "$key")"
    [[ -z "${!var+x}" && -n "$value" ]] && { export "$var=$value"; FLEET_CONFIG_VARS+=" $var"; }
  done < <(fleet_config_pairs "$cfg")
  [[ -z "${FLEET_TRUSTED_CONFIG:-}" ]] || trusted_only_settings
  return 0
}

trusted_only_settings() {
  local key value var
  while IFS=$'\t' read -r key value; do
    [[ " $FLEET_SECURE_KEYS " == *" $key "* ]] || continue
    var="$(setting_var "$key")"
    [[ -z "${!var+x}" && -n "$value" ]] && { export "$var=$value"; FLEET_CONFIG_VARS+=" $var"; }
  done < <(fleet_config_pairs "$FLEET_TRUSTED_CONFIG")
}

reload_fleet_settings() {
  local var
  for var in ${FLEET_CONFIG_VARS:-}; do [[ "$var" == FLEET_REMOTE || "$var" == FLEET_REF ]] || unset "$var"; done
  FLEET_CONFIG_VARS=""
  load_fleet_settings
}
