# shellcheck shell=bash
yaml_str() {
  jq -Rn --arg v "$1" '$v'
}

label_value() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | cut -c1-63 | sed -E 's/^-+//; s/-+$//')"
  [[ -n "$value" ]] || value="c-$(printf '%s' "$1" | sha256_hex | cut -c1-12)"
  printf '%s' "$value"
}

job_name() {
  local stem
  if [[ "$1" =~ ^([0-9]+)- ]]; then
    stem="$(printf '%s' "${BASH_REMATCH[1]}" | cut -c1-20)"
  else
    stem="$(printf '%s' "$1" | sha256_hex | cut -c1-8)"
  fi
  printf 'fleet-%s-%s' "$stem" "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-5)"
}
