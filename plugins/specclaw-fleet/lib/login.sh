# shellcheck shell=bash
capture_credential() {
  local agent="$1" tmp="$2"
  case "$agent" in
    claude)
      claude setup-token
      local token
      read -rsp "Paste the token printed above: " token || die "No token read"
      echo >&2
      [[ -n "$token" ]] || die "Empty token"
      printf '%s' "$token" > "$tmp/credential"
      ;;
    codex)
      mkdir -p "$tmp/codex"
      printf 'cli_auth_credentials_store = "file"\n' > "$tmp/codex/config.toml"
      CODEX_HOME="$tmp/codex" codex login
      [[ -s "$tmp/codex/auth.json" ]] || die "codex login wrote no auth.json"
      cp "$tmp/codex/auth.json" "$tmp/credential"
      ;;
  esac
}

fleet_login() {
  local agent="" vault=""
  while (($#)); do
    case "$1" in
      --agent) need_value "$1" "${2:-}"; agent="$2"; shift 2 ;;
      --vault) need_value "$1" "${2:-}"; vault="$2"; shift 2 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  vault="${vault:-$(cfg_val fleet.vault "")}"
  [[ -n "$vault" ]] || die "Usage: specclaw-fleet login --agent claude|codex --vault <name>"

  local upn name
  upn="$(az account show --query user.name -o tsv)" || die "Run 'az login' first"
  name="$(secret_name "$agent" "$(upn_hash "$upn")")"
  capture_credential "$agent" "$FLEET_TMPDIR"
  az keyvault secret set --vault-name "$vault" --name "$name" --file "$FLEET_TMPDIR/credential" >/dev/null \
    || die "Could not store $name (were you onboarded with specclaw-fleet onboard?)"
  echo "Stored your $agent credential as $name"
}
