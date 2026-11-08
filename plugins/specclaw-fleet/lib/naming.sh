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

rand_suffix() {
  od -An -N4 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-5
}

codex_job_name() {
  printf 'fleet-codex-%s' "${1:-$F_HASH}"
}

job_name() {
  if [[ "$2" == codex ]]; then
    codex_job_name "$3"
    return 0
  fi
  local stem
  if [[ "$1" =~ ^([0-9]+)- ]]; then
    stem="$(printf '%s' "${BASH_REMATCH[1]}" | cut -c1-20)"
  else
    stem="$(printf '%s' "$1" | sha256_hex | cut -c1-8)"
  fi
  printf 'fleet-%s-%s' "$stem" "$(rand_suffix)"
}
