#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
stub az 'echo "ERROR: Please run az login" >&2; exit 1'
stub curl 'echo "$*" >> "$TMP/curl.log"; [[ "$*" == *"-H @-"* ]] && cat >> "$TMP/curl.stdin"; case "$*" in
  *"build/definitions?name=specclaw-fleet"*) echo "{\"value\":[{\"id\":44,\"name\":\"specclaw-fleet\"}]}"; printf "\n%s" "${HTTP_CODE:-200}" ;;
  *serviceendpoint*) echo "{\"value\":[{\"name\":\"specclaw-fleet-k3s\",\"isReady\":true},{\"name\":\"specclaw-fleet-azure\",\"isReady\":true}]}"; printf "\n%s" "${HTTP_CODE:-200}" ;;
  *ghcr.io/token*) echo "{}"; printf %s "$TOKEN_CODE" ;;
esac'
export TMP
azdo_checks="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t FLEET_KUBE_CONNECTION=specclaw-fleet-k3s FLEET_AZURE_CONNECTION=specclaw-fleet-azure bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_pipeline; check_connections' _ "$FLEET_ROOT" 2>&1)"
enc="$(AZDO_ORG=o AZDO_PROJECT="Product Portal" AZDO_TOKEN=t FLEET_KUBE_CONNECTION=k FLEET_AZURE_CONNECTION=z bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; azdo_rest "x?api-version=7.1" >/dev/null; tail -1 "$TMP/curl.log"' _ "$FLEET_ROOT")"
project_encoded() { [[ "$enc" == *"dev.azure.com/o/Product%20Portal/_apis/x?api-version=7.1"* ]]; }
check "R053 azdo_rest URL-encodes the project (names may contain spaces)" project_encoded
pat_rest() { grep -q "^ok pipeline" <<<"$azdo_checks" && grep -q "^ok service-connections" <<<"$azdo_checks" && grep -q "Authorization: Basic" "$TMP/curl.stdin" \
  && ! grep -q "Authorization" "$TMP/curl.log" && ! grep -Eq "^az (devops|pipelines)" "$CALLS"; }
check "R053 AC-6 doctor checks the pipeline and connections with AZDO_TOKEN over REST, even with no az login; the auth header never appears in curl's arguments" pat_rest
mkdir -p "$TMP/pf/.specclaw" "$TMP/pf/azure-pipelines"; printf 'variables:\n  fleetKubeConnection: specclaw-fleet-hetzner\n  fleetAzureConnection: specclaw-fleet-azure\n' > "$TMP/pf/azure-pipelines/specclaw-fleet.yml"
from_file="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t SPECCLAW_DIR="$TMP/pf/.specclaw" bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_connections' _ "$FLEET_ROOT" 2>&1)"
junk_rows=1
for body in "<html>sign in</html>" "" '{"message":"x"}' '{"value":null}' '{"value":"x"}'; do
  printf '%s' "$body" > "$TMP/body"
  stub curl 'cat "$TMP/body"; printf "\n200"'
  junk="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t SPECCLAW_DIR="$TMP/pf/.specclaw" bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_pipeline; echo "rc=$?"; check_connections; echo "rc=$?"' _ "$FLEET_ROOT" 2>&1)"
  [[ "$(grep -c '^skip ' <<<"$junk")" == 2 && "$(grep -c '^rc=2' <<<"$junk")" == 2 ]] && ! grep -Eq '^(ok|missing) ' <<<"$junk" \
    || { junk_rows=0; echo "  body [$body]: $junk"; }
done
for one in "  fleetKubeConnection: k" "  fleetAzureConnection: z"; do
  mkdir -p "$TMP/one/.specclaw" "$TMP/one/azure-pipelines"; printf 'variables:\n%s\n' "$one" > "$TMP/one/azure-pipelines/specclaw-fleet.yml"
  o="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t SPECCLAW_DIR="$TMP/one/.specclaw" bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_connections; echo "rc=$?"' _ "$FLEET_ROOT" 2>&1)"
  [[ "$o" == *"not both found"*"in $TMP/one/.specclaw/../azure-pipelines/specclaw-fleet.yml"*"rc=2"* ]] || { junk_rows=0; echo "  one name [$one]: $o"; }
done
nofile="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t SPECCLAW_DIR="$TMP/nowhere/.specclaw" bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_connections; echo "rc=$?"' _ "$FLEET_ROOT" 2>&1)"
printf 'variables:\n  fleetKubeConnection: "Fleet Hetzner K8s"   # spaces\n  fleetAzureConnection: Specclaw-Fleet-Azure # case\n' > "$TMP/pf/azure-pipelines/specclaw-fleet.yml"
stub curl 'echo "$*" >> "$TMP/curl.log"; echo "{\"value\":[{\"name\":\"Fleet Hetzner K8s\",\"isReady\":true},{\"name\":\"specclaw-fleet-azure\",\"isReady\":true}]}"; printf "\n200"'
spaced="$(AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t SPECCLAW_DIR="$TMP/pf/.specclaw" bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_connections' _ "$FLEET_ROOT" 2>&1)"
names_from_pipeline() { [[ "$spaced" == "ok service-connections: ready" ]] && grep -q "endpointNames=Fleet%20Hetzner%20K8s,Specclaw-Fleet-Azure" "$TMP/curl.log" || return 1; [[ "$from_file" == "missing service-connections: specclaw-fleet-hetzner" ]]; }
junk_is_skip() { (( junk_rows == 1 )) && [[ "$nofile" == *"skip service-connections: fleetKubeConnection and fleetAzureConnection not both found"*"rc=2"* ]]; }
check "R053 doctor checks the connection names the pipeline YAML uses: quoted names with spaces, case-insensitive match, encoded query" names_from_pipeline
check "R053 any malformed AzDO answer (html, empty, no value, null, non-list) is skip for both REST checks; unreadable pipeline YAML is skip" junk_is_skip
stub curl 'echo "$*" >> "$TMP/curl.log"; case "$*" in *ghcr.io/token*) echo "{}"; printf %s "$TOKEN_CODE" ;; esac'
words=1
for code in 401 403; do
  out="$(TOKEN_CODE=$code FLEET_IMAGE=ghcr.io/o/x:1 bash -c 'source "$1/lib/common.sh"; source "$1/lib/azdo-rest.sh"; source "$1/lib/doctor-azure.sh"; check_image; echo "rc=$?"' _ "$FLEET_ROOT")"
  [[ "$out" == *"missing image: ghcr.io/o/x:1: package missing or private"*"rc=1"* ]] || { words=0; echo "  $code: $out"; }
done
token_wording() { (( words == 1 )); }
check "R053 AC-6 a ghcr.io token refused with 401 or 403 is reported as package missing or private" token_wording
stub_az
cl=1
for row in "FLEET_CLUSTER_NAME=bistec-dev-uat FLEET_KUBE_CONTEXT=fleet|bistec-dev-uat" "FLEET_KUBE_CONTEXT=ctx-a|ctx-a" "X=1|k3s-a"; do
  reset_env; eval "${row%%|*} dispatch" || { cl=0; cat "$TMP/out"; }
  grep -q "cluster=${row#*|} " "$CALLS" || { cl=0; echo "  ${row%%|*}: $(grep -o 'cluster=[^ ]*' "$CALLS")"; }
done
cluster_order() { (( cl == 1 )); }
check "R053 AC-6 the run record's cluster= is FLEET_CLUSTER_NAME, then FLEET_KUBE_CONTEXT, then the current context" cluster_order
reset_env; FLEET_TRUSTED_COMMIT=0123abc dispatch; trusted_rec="$(grep -o 'settings_commit=[^ ]*' "$CALLS")"
reset_env; dispatch; local_rec="$(grep -o 'settings_commit=[^ ]*' "$CALLS")"
settings_recorded() { [[ "$trusted_rec" == settings_commit=0123abc && "$local_rec" == settings_commit=local ]]; }
check "R053 the run record pins the trusted-branch commit its security settings came from" settings_recorded
prompt_delivery() { grep -m1 '^PROMPT=' "$FLEET_ROOT/image/entrypoint.sh" | grep -q "this pod pushes the change branch and opens a PR if none exists.*do not report it as unpushed"; }
check "R053 AC-6 the agent prompt states that the pod delivers committed work" prompt_delivery
export AZDO_ORG=o AZDO_PROJECT=p FLEET_REMOTE=local
https_local_remote
reset_env; git init -q --bare "$TMP/remote.git"; git -C "$TMP/repo" remote add local "$TMP/remote.git"
git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m s && git -C "$TMP/repo" push -q local HEAD:main
: > "$CALLS"; (cd "$TMP/repo" && "$FLEET" trigger 999-nope) > "$TMP/out" 2>&1; miss_rc=$?
names_missing() { (( miss_rc == 1 )) && grep -q "no change 999-nope on local/main" "$TMP/out" && ! grep -q "azdo-issue" "$CALLS"; }
check "R053 AC-6 trigger names a change that does not exist on the pushed ref" names_missing
printf 'azdo:\n  fleet_states:\n    failed: Failed\nfleet:\n  vault: pushed-kv\n' > "$SPECCLAW_DIR/config.yaml"
git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q -m cfg && git -C "$TMP/repo" push -q local HEAD:main
printf 'azdo:\n  fleet_states:\n    failed: Failed\nfleet:\n  vault: local-kv\n' > "$SPECCLAW_DIR/config.yaml"
: > "$CALLS"; (cd "$TMP/repo" && env -u FLEET_VAULT "$FLEET" trigger "$CHANGE") > "$TMP/out-cfg" 2>&1
local_rows=1
for row in "FLEET_KUBE_CONTEXT=local-ctx|local-ctx|unset" "KUBECONFIG=./k/local|none|$TMP/repo/k/local" "FLEET_KUBE_CONTEXT=local-ctx KUBECONFIG=/abs/k|local-ctx|/abs/k"; do
  IFS='|' read -r envs want_ctx want_cfg <<<"$row"; printf '%s\n' $envs > "$SPECCLAW_DIR/.env"; rm -f "$KCTX" "$KCTX.cfg"
  git -C "$TMP/repo" update-ref -d refs/claims 2>/dev/null; rm -rf "$CLAIMS"/wi-*
  (cd "$TMP/repo" && env -u FLEET_VAULT -u FLEET_KUBE_CONTEXT -u KUBECONFIG "$FLEET" trigger "$CHANGE" --direct --retry) > "$TMP/out-direct" 2>&1
  [[ -s "$KCTX" && "$(sort -u "$KCTX")" == "$want_ctx" && "$(sort -u "$KCTX.cfg")" == "$want_cfg" ]] \
    || { local_rows=0; echo "  [$envs]: ctx=$(sort -u "$KCTX" 2>/dev/null | tr '\n' ' ') cfg=$(sort -u "$KCTX.cfg" 2>/dev/null | tr '\n' ' ') $(tail -2 "$TMP/out-direct")"; }
done
rm -f "$SPECCLAW_DIR/.env"
local_kept() { (( local_rows == 1 )); }
check "R053 trigger --direct keeps this machine's cluster pointer (.env context, kubeconfig, both) when it reloads the pushed fleet: settings" local_kept
pushed_vault() { grep -q "keyvault secret show.*pushed-kv" "$CALLS" && ! grep -q "local-kv" "$CALLS"; }
check "R053 trigger gates with the fleet: settings of the pushed ref, not unpushed local config" pushed_vault
finish
