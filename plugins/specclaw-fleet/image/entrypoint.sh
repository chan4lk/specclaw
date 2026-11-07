#!/usr/bin/env bash
set -uo pipefail
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY CODEX_API_KEY

STATUS="${FLEET_STATUS_DIR:-/fleet/status}"
WORK="${FLEET_WORK:-/fleet/work}"
CRED="${FLEET_CRED:-/run/fleet/credential}"
SEED="${FLEET_SEED:-/opt/fleet/home-seed}"
REPO="$WORK/repo"
CODEX_DIR="${FLEET_CODEX_HOME:-/fleet/codex}"
PROMPT="Run the specclaw lifecycle headless for change $FLEET_CHANGE. Use the specclaw skills in order: plan (only if the change has no tasks yet), build, verify, then the specclaw-sync pr-azdo skill. When verify fails only because specclaw-review reports blocker or major findings, run the specclaw-review loop as its skill describes (fix by class, add variant tests, commit, re-review the delta, then the final pass) for at most ${FLEET_REVIEW_ROUNDS:-5} fix rounds; stop if the review escalates (exit 4) or the rounds run out. Then re-run verify and, only on PASS, pr-azdo. Nobody is watching: never ask a question. If a phase fails, stop and report why."
agent_pid=""
for lib in tracker egress-gate claude-auth workspace draft-pr; do
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/$lib.sh"
done

finish() { printf '%s\n' "$1" > "$STATUS/exit"; exit 0; }

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
  mkdir -p "$CODEX_DIR"
  cp -a "$SEED/.codex/." "$CODEX_DIR/" 2>/dev/null || true
  cp "$CRED" "$CODEX_DIR/auth.json"
  grep -q cli_auth_credentials_store "$CODEX_DIR/config.toml" 2>/dev/null \
    || printf 'cli_auth_credentials_store = "file"\n' >> "$CODEX_DIR/config.toml"
  sha256sum "$CODEX_DIR/auth.json" | cut -d' ' -f1 > "$STATUS/seed.sha"
}

run_agent() {
  prepare_workspace
  case "$FLEET_AGENT" in
    claude)
      seed_claude_auth
      claude -p "$PROMPT" --dangerously-skip-permissions --output-format json > "$STATUS/agent.log" 2>&1 &
      ;;
    codex)
      seed_codex
      CODEX_HOME="$CODEX_DIR" \
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

wait_for_egress || { record state=failed exit=egress-not-ready; finish 2; }
clone || { record state=failed exit=clone-failed; finish 2; }
if [[ -n "${FLEET_COMMIT:-}" ]] && ! git -C "$REPO" merge-base --is-ancestor "$FLEET_COMMIT" HEAD; then
  record state=failed exit=commit-not-on-ref "dispatched_commit=$FLEET_COMMIT"
  finish 2
fi
STATE="$REPO/.specclaw/changes/$FLEET_CHANGE/state.json"
[[ "$(jq -r '.phases.proposal.status // empty' "$STATE" 2>/dev/null)" == approved ]] \
  || { record state=failed exit=not-approved-at-ref; finish 2; }
record state=running "built_commit=$(git -C "$REPO" rev-parse HEAD)"
cd "$REPO" || finish 2
rc=0; run_agent || rc=$?
branch="$(push_change_branch)"
read -r pr draft < <(ensure_pr "$branch")
show_agent_log
record "state=$([[ -n "$pr" ]] && echo pr_open || echo failed)" "exit=$rc" "branch=$branch" "pr=${pr:-none}" "draft=${draft:-false}"
finish "$rc"
