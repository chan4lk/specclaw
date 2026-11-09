#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
mkdir -p "$TMP/sc"
cfg() { printf '%s\n' "$@" > "$TMP/sc/config.yaml"; }
load() {
  env -u FLEET_VAULT -u FLEET_KUBE_CONTEXT -u FLEET_IMAGE -u KUBECONFIG -u FLEET_DEADLINE_MINUTES "$@" bash -c '
    SPECCLAW_DIR="$1"; source "$2/lib/common.sh"; source "$2/lib/settings.sh"; load_local_env; load_fleet_settings || exit $?
    echo "vault=[${FLEET_VAULT-unset}] ctx=[${FLEET_KUBE_CONTEXT-unset}] image=[${FLEET_IMAGE-unset}] kc=[${KUBECONFIG-unset}] dl=[${FLEET_DEADLINE_MINUTES-unset}]"' _ "$TMP/sc" "$FLEET_ROOT" 2>&1
}
rows=1
row() { local want="$1"; shift; local got; got="$(load "$@")"; [[ "$got" == *"$want"* ]] || { rows=0; echo "  want [$want] got [$got]"; }; }
cfg 'git:' '  vault: not-this' 'fleet:' '  vault: kv-scfleet-965892   # the vault' "  kube_context: 'bistec-dev-uat'" \
    '  image: "ghcr.io/o/specclaw-fleet:0.9.0"' $'  kubeconfig: /k/cfg\r' '  deadline_minutes: 90' 'azdo:' '  vault: nor-this'
row "vault=[kv-scfleet-965892] ctx=[unset] image=[ghcr.io/o/specclaw-fleet:0.9.0] kc=[unset] dl=[90]"
row "WARNING: ignored fleet.kube_context"; row "set KUBECONFIG in"
row "vault=[env-kv]" FLEET_VAULT=env-kv
printf 'FLEET_KUBE_CONTEXT=bistec-dev-uat\nKUBECONFIG=./scratch/hetzner/kubeconfig\n' > "$TMP/sc/.env"
row "ctx=[bistec-dev-uat] image=[ghcr.io/o/specclaw-fleet:0.9.0] kc=[$(cd "$TMP" && pwd)/scratch/hetzner/kubeconfig]"
row "ctx=[mine] image=[ghcr.io/o/specclaw-fleet:0.9.0] kc=[/abs/k]" FLEET_KUBE_CONTEXT=mine KUBECONFIG=/abs/k
row "ctx=[] image=[ghcr.io/o/specclaw-fleet:0.9.0] kc=[rel/k]" FLEET_KUBE_CONTEXT= KUBECONFIG=rel/k
rm -f "$TMP/sc/.env"
cfg 'fleet:' '  vault: kv1' '  colour: blue'
row "WARNING: ignored unknown fleet.colour" ; row "vault=[kv1]"
cfg 'fleet:' '  vault: top' '  extra:' '    vault: nested'
row "WARNING: ignored nested key vault under fleet:"; row "vault=[top]"
cfg 'fleet:' '  image: ghcr.io/o/x@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
row "image=[ghcr.io/o/x@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef]"
for p in /Users/someone/very/long/path/to/a/pipeline-for-the-bistec-dev-uat-cluster-isolated.yml \
         pipelines/azure-devops/fleet/specclaw-fleet-dispatch-hosted-bistec-dev-uat.yml; do
  cfg 'fleet:' '  vault: kv1' "  pipeline_file: $p"; row "vault=[kv1]"
done
cfg 'fleet:' '  deadline_minutes: x[$(touch /tmp/fleet-pwned)]'; out="$(load)"; hostile_rc=$?
cfg 'fleet:' '  deadline_minutes: 90abc'; out2="$(load)"; hostile2_rc=$?
hostile_refused() { (( hostile_rc != 0 && hostile2_rc != 0 )) && [[ "$out" == *"fleet.deadline_minutes"*"whole number"* && "$out2" == *"whole number"* && ! -e /tmp/fleet-pwned ]]; }
printf 'fleet:\n  vault: trusted-kv\n  image: ghcr.io/o/x:1\n  deadline_minutes: 30\n' > "$TMP/trusted.yaml"
cfg 'fleet:' '  vault: trusted-kv'; same="$(load FLEET_TRUSTED_CONFIG="$TMP/trusted.yaml")"
cfg 'fleet:' '  vault: evil-kv'; evil="$(load FLEET_TRUSTED_CONFIG="$TMP/trusted.yaml")"; evil_rc=$?
cfg 'fleet:' '  image: ghcr.io/evil/x:1'; evil_img="$(load FLEET_TRUSTED_CONFIG="$TMP/trusted.yaml")"; evil_img_rc=$?
cfg 'fleet:' '  deadline_minutes: 99999'; evil_dl="$(load FLEET_TRUSTED_CONFIG="$TMP/trusted.yaml")"; evil_dl_rc=$?
cfg 'fleet:' '  pipeline: p'; inherit="$(load FLEET_TRUSTED_CONFIG="$TMP/trusted.yaml")"
trusted_only() {
  [[ "$same" == *"vault=[trusted-kv]"*"image=[ghcr.io/o/x:1]"*"dl=[30]"* ]] && (( evil_rc != 0 && evil_img_rc != 0 && evil_dl_rc != 0 )) \
    && [[ "$evil" == *"fleet.vault on this branch differs from the trusted branch"* && "$evil_img" == *"fleet.image on this branch differs"* ]] \
    && [[ "$inherit" == *"vault=[trusted-kv]"*"image=[ghcr.io/o/x:1]"*"dl=[30]"* && "$evil_dl" == *"fleet.deadline_minutes on this branch differs"* ]]
}
check "R053 a non-numeric fleet.deadline_minutes (incl. an arithmetic-injection payload) is refused at load and never evaluated" hostile_refused
check "R053 with a trusted config, security settings come only from it: a branch value that differs fails closed; a branch without them inherits" trusted_only
secret_rows=1 T="~"
for v in "sk-ant-oat01-abcdef" "eyJhbGciOiJIUzI1NiJ9.e30.x" "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQR" \
         "ab/cdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMN+OPQRS/tuvw==" "/home/u/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQR" "$T/abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRx" \
         "/Abcdefghijklmnopqrstuvwxyz01234/56789ABCDEFGHIJKLMNOPQRSTUVWX/yz0123456789abcdefghij+k=="; do
  cfg 'fleet:' "  vault: $v"; out="$(load)"; rc=$?
  (( rc != 0 )) && [[ "$out" == *"fleet.vault"*"looks like a secret"* && "$out" != *"$v"* ]] || { secret_rows=0; echo "  secret not refused: rc=$rc $out"; }
done
precedence() { (( rows == 1 )); }
secrets() { (( secret_rows == 1 )); }
check "R053 AC-1 fleet: config fills unset env only; env (even empty) wins; quotes, comments, CRLF; only the fleet: block; unknown keys warn; the local cluster pointer comes only from env or .specclaw/.env (relative KUBECONFIG resolved at the repo root), never fleet:; long paths are not secrets" precedence
check "R053 AC-1 a secret-looking fleet: value is refused without printing it" secrets
mkdir -p "$TMP/repo/.specclaw"; printf 'fleet:\n  vault: cfg-kv\n' > "$TMP/repo/.specclaw/config.yaml"
flag_out="$(cd "$TMP/repo" && "$FLEET" dispatch x --vault flag-kv --dry-run 2>&1)"
flag_wins() { [[ "$flag_out" != *"No Key Vault"* ]] && ! grep -q "cfg-kv" <<<"$flag_out"; }
check "R053 AC-1 a flag beats config" flag_wins
export TMP AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/
for t in dispatch.yml dispatch-hosted.yml; do
  stub specclaw-fleet 'echo "ctx=[${FLEET_KUBE_CONTEXT-unset}]" >> "$TMP/ctx"'
  stub git 'case "$1" in fetch) exit 0 ;; show) printf "fleet:\n  vault: trusted-kv\n" ;; rev-parse) echo 0123abc ;; esac'
  sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/$t" | sed '1d;$d;s/^        //' > "$TMP/step.sh"
  mkdir -p "$TMP/p/.specclaw/changes/049-x"; echo '{"phase":"proposal","phases":{"proposal":{"status":"approved"}}}' > "$TMP/p/.specclaw/changes/049-x/state.json"
  (cd "$TMP/p" && FLEET_REF=refs/heads/main FLEET_KUBE_CONTEXT=bistec-dev-uat bash "$TMP/step.sh") >/dev/null 2>&1
done
cleared() { [[ "$(sort -u "$TMP/ctx")" == "ctx=[]" ]] && [[ $(wc -l < "$TMP/ctx") -eq 2 ]]; }
check "R053 AC-2 both pipeline steps clear FLEET_KUBE_CONTEXT so config cannot point the hosted run at another context" cleared
finish
