# shellcheck shell=bash
ensure_placeholder() {
  local err="$FLEET_TMPDIR/show.err"
  az keyvault secret show --vault-name "$1" --name "$2" >/dev/null 2>"$err" && return 0
  secret_not_found "$err" || die "Could not check $2 in $1, leaving it untouched: $(head -n1 "$err")"
  az keyvault secret set --vault-name "$1" --name "$2" --value __unset__ >/dev/null
}

grant_secret_officer() {
  local who="$1" scope="$2"
  [[ -n "$(az role assignment list --assignee "$who" --role "Key Vault Secrets Officer" --scope "$scope" --query '[].id' -o tsv)" ]] \
    || az role assignment create --assignee "$who" --role "Key Vault Secrets Officer" --scope "$scope" >/dev/null
}

fleet_onboard() {
  local upn="" vault="" writer=""
  while (($#)); do
    case "$1" in
      --vault) need_value "$1" "${2:-}"; vault="$2"; shift 2 ;;
      --writer) need_value "$1" "${2:-}"; writer="$2"; shift 2 ;;
      -*) die "Unknown flag: $1" ;;
      *) upn="$1"; shift ;;
    esac
  done
  [[ -n "$upn" && -n "$vault" ]] || die "Usage: specclaw-fleet onboard <upn> --vault <name> [--writer <object-id>]"
  writer="${writer:-${FLEET_VAULT_WRITER:-}}"
  [[ -n "$writer" ]] || warn "no --writer / FLEET_VAULT_WRITER: codex runs for $upn will not persist refreshed tokens until the write-back service principal is granted codex-auth-$(upn_hash "$upn")"

  local h vault_id agent name scope
  h="$(upn_hash "$upn")"
  vault_id="$(az keyvault show --name "$vault" --query id -o tsv)" || die "Key Vault not found: $vault"
  for agent in claude codex; do
    name="$(secret_name "$agent" "$h")"
    ensure_placeholder "$vault" "$name"
    scope="$vault_id/secrets/$name"
    grant_secret_officer "$upn" "$scope"
    if [[ "$agent" == codex && -n "$writer" ]]; then grant_secret_officer "$writer" "$scope"; fi
    echo "Onboarded $upn: $name"
  done
}
