#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

stub_az
stub claude 'echo "Open https://claude.ai/oauth to authorize"'
stub codex 'grep -q file "$CODEX_HOME/config.toml" && echo "{\"tokens\":\"CODEX-CANARY\"}" > "$CODEX_HOME/auth.json"'
export AZ_UPN=bob@contoso.com TMPDIR="$TMP/tmpdir"
mkdir -p "$TMPDIR"
h="$(hash_of "$AZ_UPN")"

echo "sk-ant-oat01-CLAUDE-CANARY" | "$FLEET" login --agent claude --vault v > "$TMP/out" 2>&1
"$FLEET" login --agent codex --vault v >> "$TMP/out" 2>&1

stored() { [[ "$(cat "$KV/claude-token-$h")" == sk-ant-oat01-CLAUDE-CANARY ]] && grep -q CODEX-CANARY "$KV/codex-auth-$h"; }
no_leak() { ! grep -q CANARY "$TMP/out"; }
cleaned() { [[ -z "$(ls -A "$TMPDIR")" ]]; }

check "AC3 tokens stored under the caller's own hash" stored
check "AC3 no token on stdout or stderr" no_leak
check "AC3 temp dir removed" cleaned
finish
