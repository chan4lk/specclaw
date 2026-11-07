#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

stub_az
h="$(hash_of Alice@Contoso.com)"
"$FLEET" onboard Alice@Contoso.com --vault v > "$TMP/out" 2>&1
echo real-token > "$KV/claude-token-$h"
"$FLEET" onboard Alice@Contoso.com --vault v >> "$TMP/out" 2>&1

secret_scoped() {
  [[ "$(sort "$KV/ra")" == "$(printf '/vaults/v/secrets/claude-token-%s\n/vaults/v/secrets/codex-auth-%s' "$h" "$h")" ]]
}
no_vault_scope() { ! grep -qxF /vaults/v "$KV/ra"; }
idempotent() { [[ "$(cat "$KV/claude-token-$h")" == real-token && "$(cat "$KV/codex-auth-$h")" == __unset__ ]]; }

check "AC2 role assignments scoped to the user's two secrets, no duplicates" secret_scoped
check "AC2 no vault-scope assignment" no_vault_scope
check "AC2 re-run keeps an existing secret value" idempotent
finish
