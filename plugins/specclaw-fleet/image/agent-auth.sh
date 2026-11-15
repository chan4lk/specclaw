# shellcheck shell=bash
seed_claude_auth() {
  mkdir -p "$HOME/.fleet"
  (umask 077 && tr -d '\n' < "$CRED" > "$HOME/.fleet/claude-token")
  CLAUDE_CODE_OAUTH_TOKEN="$(cat "$HOME/.fleet/claude-token")"
  export CLAUDE_CODE_OAUTH_TOKEN
}

seed_codex() {
  mkdir -p "$CODEX_DIR"
  cp -a "$SEED/.codex/." "$CODEX_DIR/" 2>/dev/null || true
  cp "$CRED" "$CODEX_DIR/auth.json"
  grep -q cli_auth_credentials_store "$CODEX_DIR/config.toml" 2>/dev/null \
    || printf 'cli_auth_credentials_store = "file"\n' >> "$CODEX_DIR/config.toml"
  sha256sum "$CODEX_DIR/auth.json" | cut -d' ' -f1 > "$STATUS/seed.sha"
}
