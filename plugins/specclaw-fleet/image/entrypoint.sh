#!/usr/bin/env bash
set -uo pipefail
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY

STATUS="${FLEET_STATUS_DIR:-/fleet/status}"
WORK="${FLEET_WORK:-/fleet/work}"
CRED="${FLEET_CRED:-/run/fleet/credential}"
SEED="${FLEET_SEED:-/opt/fleet/home-seed}"
REPO="$WORK/repo"
PROMPT="Run the specclaw lifecycle headless for change $FLEET_CHANGE. Use the specclaw skills in order: plan (only if the change has no tasks yet), build, verify, then the specclaw-sync pr-azdo skill. Nobody is watching: never ask a question. If a phase fails, stop and report why."
agent_pid=""

finish() { printf '%s\n' "$1" > "$STATUS/exit"; exit 0; }

tracker_dir() {
  local dir="$WORK/fallback/.specclaw"
  if [[ -d "$REPO/.specclaw/changes/$FLEET_CHANGE" ]]; then printf '%s' "$REPO/.specclaw"; return 0; fi
  mkdir -p "$dir/changes/$FLEET_CHANGE"
  printf '**Azure Boards Work Item:** [#%s](fleet)\n' "${FLEET_WORK_ITEM:-0}" > "$dir/changes/$FLEET_CHANGE/status.md"
  printf '%s' "$dir"
}

record() {
  specclaw-azdo-issue fields "$(tracker_dir)" "$FLEET_CHANGE" "$@" >/dev/null 2>&1 \
    || echo "WARNING: work item update failed: $*" >&2
}

on_term() {
  [[ -n "$agent_pid" ]] && kill "$agent_pid" 2>/dev/null
  record state=failed exit=deadline
  finish 143
}
trap on_term TERM

clone() {
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf ':%s' "$AZDO_TOKEN" | base64 | tr -d '\n')"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0
  git clone --quiet --branch "$FLEET_REF" "$FLEET_REPO_URL" "$REPO"
}

seed_codex() {
  mkdir -p "$HOME/.codex"
  cp "$CRED" "$HOME/.codex/auth.json"
  grep -q cli_auth_credentials_store "$HOME/.codex/config.toml" 2>/dev/null \
    || printf 'cli_auth_credentials_store = "file"\n' >> "$HOME/.codex/config.toml"
  sha256sum "$HOME/.codex/auth.json" | cut -d' ' -f1 > "$STATUS/seed.sha"
}

run_agent() {
  cp -a "$SEED/." "$HOME/" 2>/dev/null || true
  case "$FLEET_AGENT" in
    claude)
      CLAUDE_CODE_OAUTH_TOKEN="$(cat "$CRED")" \
        claude -p "$PROMPT" --dangerously-skip-permissions --output-format json > "$STATUS/agent.log" 2>&1 &
      ;;
    codex)
      seed_codex
      CODEX_HOME="$HOME/.codex" \
        codex exec --dangerously-bypass-approvals-and-sandbox "$PROMPT" > "$STATUS/agent.log" 2>&1 &
      ;;
    *) return 2 ;;
  esac
  agent_pid=$!
  (sleep "${FLEET_AGENT_TIMEOUT:-7200}" && kill -TERM $$) &
  local watchdog=$! rc=0
  wait "$agent_pid" || rc=$?
  kill "$watchdog" 2>/dev/null
  return "$rc"
}

clone || { record state=failed exit=clone-failed; finish 2; }
record state=running
cd "$REPO" || finish 2
run_agent
rc=$?
pr="$(jq -r '.phases.pr.url // empty' "$REPO/.specclaw/changes/$FLEET_CHANGE/state.json" 2>/dev/null)"
if [[ -n "$pr" ]]; then record state=pr_open "exit=$rc"; else record state=failed "exit=$rc"; fi
finish "$rc"
