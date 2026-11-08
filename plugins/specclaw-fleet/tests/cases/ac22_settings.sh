#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
mkdir -p "$TMP/sc"
cfg() { printf '%s\n' "$@" > "$TMP/sc/config.yaml"; }
load() {
  env -u FLEET_VAULT -u FLEET_KUBE_CONTEXT -u FLEET_IMAGE -u KUBECONFIG -u FLEET_DEADLINE_MINUTES "$@" bash -c '
    SPECCLAW_DIR="$1"; source "$2/lib/common.sh"; source "$2/lib/settings.sh"; load_fleet_settings || exit $?
    echo "vault=[${FLEET_VAULT-unset}] ctx=[${FLEET_KUBE_CONTEXT-unset}] image=[${FLEET_IMAGE-unset}] kc=[${KUBECONFIG-unset}] dl=[${FLEET_DEADLINE_MINUTES-unset}]"' _ "$TMP/sc" "$FLEET_ROOT" 2>&1
}
rows=1
row() { local want="$1"; shift; local got; got="$(load "$@")"; [[ "$got" == *"$want"* ]] || { rows=0; echo "  want [$want] got [$got]"; }; }
cfg 'git:' '  vault: not-this' 'fleet:' '  vault: kv-scfleet-965892   # the vault' "  kube_context: 'bistec-dev-uat'" \
    '  image: "ghcr.io/o/specclaw-fleet:0.9.0"' $'  kubeconfig: /k/cfg\r' '  deadline_minutes: 90' 'azdo:' '  vault: nor-this'
row "vault=[kv-scfleet-965892] ctx=[bistec-dev-uat] image=[ghcr.io/o/specclaw-fleet:0.9.0] kc=[/k/cfg] dl=[90]"
row "vault=[env-kv] ctx=[bistec-dev-uat]" FLEET_VAULT=env-kv
row "ctx=[]" FLEET_KUBE_CONTEXT=
cfg 'fleet:' '  vault: kv1' '  colour: blue'
row "WARNING: ignored unknown fleet.colour" ; row "vault=[kv1]"
cfg 'fleet:' '  image: ghcr.io/o/x@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
row "image=[ghcr.io/o/x@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef]"
secret_rows=1
for v in "sk-ant-oat01-abcdef" "eyJhbGciOiJIUzI1NiJ9.e30.x" "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQR"; do
  cfg 'fleet:' "  vault: $v"; out="$(load)"; rc=$?
  (( rc != 0 )) && [[ "$out" == *"fleet.vault"*"looks like a secret"* && "$out" != *"$v"* ]] || { secret_rows=0; echo "  secret not refused: rc=$rc $out"; }
done
precedence() { (( rows == 1 )); }
secrets() { (( secret_rows == 1 )); }
check "R053 AC-1 fleet: config fills unset env only; env (even empty) wins; quotes, comments, CRLF; only the fleet: block; unknown keys warn" precedence
check "R053 AC-1 a secret-looking fleet: value is refused without printing it" secrets
mkdir -p "$TMP/repo/.specclaw"; printf 'fleet:\n  vault: cfg-kv\n' > "$TMP/repo/.specclaw/config.yaml"
flag_out="$(cd "$TMP/repo" && "$FLEET" dispatch x --vault flag-kv --dry-run 2>&1)"
flag_wins() { [[ "$flag_out" != *"No Key Vault"* ]] && ! grep -q "cfg-kv" <<<"$flag_out"; }
check "R053 AC-1 a flag beats config" flag_wins
export TMP AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/
for t in dispatch.yml dispatch-hosted.yml; do
  stub specclaw-fleet 'echo "ctx=[${FLEET_KUBE_CONTEXT-unset}]" >> "$TMP/ctx"'
  sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/$t" | sed '1d;$d;s/^        //' > "$TMP/step.sh"
  mkdir -p "$TMP/p/.specclaw/changes/049-x"; echo '{"phase":"proposal","phases":{"proposal":{"status":"approved"}}}' > "$TMP/p/.specclaw/changes/049-x/state.json"
  (cd "$TMP/p" && FLEET_REF=refs/heads/main FLEET_KUBE_CONTEXT=bistec-dev-uat bash "$TMP/step.sh") >/dev/null 2>&1
done
cleared() { [[ "$(sort -u "$TMP/ctx")" == "ctx=[]" ]] && [[ $(wc -l < "$TMP/ctx") -eq 2 ]]; }
check "R053 AC-2 both pipeline steps clear FLEET_KUBE_CONTEXT so config cannot point the hosted run at another context" cleared
finish
