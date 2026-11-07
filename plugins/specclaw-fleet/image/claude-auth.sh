# shellcheck shell=bash
seed_claude_auth() {
  local settings="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  [[ -s "$settings" ]] || echo '{}' > "$settings"
  jq --rawfile token "$CRED" '.env.CLAUDE_CODE_OAUTH_TOKEN = ($token | rtrimstr("\n"))' "$settings" > "$settings.tmp" \
    && mv "$settings.tmp" "$settings"
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$CRED")"
  export CLAUDE_CODE_OAUTH_TOKEN
}
