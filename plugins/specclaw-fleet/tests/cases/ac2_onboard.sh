#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

stub_az
h="$(hash_of Alice@Contoso.com)"
"$FLEET" onboard Alice@Contoso.com --vault v > "$TMP/out" 2>&1
echo real-token > "$KV/claude-token-$h"
"$FLEET" onboard Alice@Contoso.com --vault v --writer sp-writer >> "$TMP/out" 2>&1
"$FLEET" onboard bob@contoso.com --vault v > "$TMP/nowriter" 2>&1
AZ_FAIL=1 "$FLEET" onboard Alice@Contoso.com --vault v >> "$TMP/out" 2>&1
throttled_rc=$?

secret_scoped() {
  [[ "$(grep -v "^bob@" "$KV/ra" | sort)" == "$(printf 'Alice@Contoso.com /vaults/v/secrets/claude-token-%s\nAlice@Contoso.com /vaults/v/secrets/codex-auth-%s\nsp-writer /vaults/v/secrets/codex-auth-%s' "$h" "$h" "$h")" ]]
}
no_vault_scope() { ! grep -q " /vaults/v$" "$KV/ra"; }
placeholder_only_when_not_found() {
  (( throttled_rc != 0 )) && [[ "$(cat "$KV/claude-token-$h")" == real-token && "$(cat "$KV/codex-auth-$h")" == __unset__ ]]
}

check "AC2 user scoped to their two secrets, writer to their codex secret only, no duplicates" secret_scoped
check "AC2 no vault-scope assignment" no_vault_scope
warns_without_writer() { grep -q "WARNING: no --writer" "$TMP/nowriter"; }
check "AC2 onboarding without a writer warns that codex refresh will not persist" warns_without_writer
check "AC2 placeholder written only on NotFound: existing kept, vault error refuses" placeholder_only_when_not_found
finish
