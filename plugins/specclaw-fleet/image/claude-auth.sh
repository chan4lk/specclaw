# shellcheck shell=bash
seed_claude_auth() {
  mkdir -p "$HOME/.fleet"
  (umask 077 && tr -d '\n' < "$CRED" > "$HOME/.fleet/claude-token")
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$HOME/.fleet/claude-token")"
  export CLAUDE_CODE_OAUTH_TOKEN
}
