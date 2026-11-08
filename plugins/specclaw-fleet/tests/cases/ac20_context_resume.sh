#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
ctx_rows=1
for agent in claude codex; do
  for ctx in fleet-ctx ""; do
    reset_env; rm -f "$KCTX"; [[ "$agent" == codex ]] && seed_codex_job '{"succeeded":1}'
    FLEET_KUBE_CONTEXT="$ctx" dispatch --agent "$agent" || { ctx_rows=0; echo "  $agent [$ctx]: $(cat "$TMP/out")"; continue; }
    want="${ctx:-none}"; cluster="${ctx:-k3s-a}"
    [[ -s "$KCTX" && -z "$(grep -vx "$want" "$KCTX")" ]] || { ctx_rows=0; echo "  $agent [$ctx]: contexts $(sort -u "$KCTX" | tr '\n' ' ')"; }
    grep -q "cluster=$cluster" "$CALLS" || { ctx_rows=0; echo "  $agent [$ctx]: cluster not $cluster"; }
  done
done
uses_context() { (( ctx_rows == 1 )); }
check "R10 every dispatch kubectl call (create, get, delete, list) honours FLEET_KUBE_CONTEXT; the record names it" uses_context

url_of() { local d; d="$(mktemp -d "$TMP/u.XXXX")"; (git init -q "$d" && mkdir "$d/.specclaw" && git -C "$d" remote add origin "$1" && export SPECCLAW_DIR="$d/.specclaw" \
  && source "$FLEET_ROOT/lib/common.sh" && https_repo_url origin) 2>&1; }
urls_ok() {
  [[ "$(url_of git@ssh.dev.azure.com:v3/o/p/r)" == https://dev.azure.com/o/p/_git/r ]] \
    && [[ "$(url_of https://u:pat@dev.azure.com/o/p/_git/r)" == https://dev.azure.com/o/p/_git/r ]] \
    && [[ "$(url_of git@github.com:o/r.git)" == *"not an https URL"* ]] \
    && [[ "$(url_of ssh://git@host/r)" == *"not an https URL"* ]]
}
check "R10 repo URL: AzDO SSH maps to https, credentials are stripped, other SSH remotes name the cause" urls_ok

mkdir -p "$TMP/sc"; printf 'AZDO_ORG=fileorg\nAZDO_PROJECT=fileproj\nAZDO_TOKEN=filetok\n' > "$TMP/sc/.env"
partial="$(export SPECCLAW_DIR="$TMP/sc" AZDO_ORG=envorg; unset AZDO_PROJECT AZDO_TOKEN; source "$FLEET_ROOT/lib/common.sh"; load_azdo_env; echo "$AZDO_ORG $AZDO_PROJECT $AZDO_TOKEN")"
per_key() { [[ "$partial" == "envorg fileproj filetok" ]]; }
check "R10 .env fills only the keys the environment leaves unset" per_key

stub curl 'echo "$*" >> "$TMP/curl.log"; case "$*" in *manifests*) printf 200 ;; *) echo "{\"token\":\"t\"}" ;; esac'
export TMP
(unset FLEET_IMAGE; source "$FLEET_ROOT/lib/common.sh"; source "$FLEET_ROOT/lib/doctor-azure.sh"; check_image) > "$TMP/img" 2>&1
version="$(jq -r .version "$FLEET_ROOT/.claude-plugin/plugin.json")"
default_image_checked() { grep -q "chan4lk/specclaw-fleet/manifests/$version" "$TMP/curl.log" && grep -q "^ok image" "$TMP/img"; }
check "R10 doctor checks the same default image dispatch would run" default_image_checked
finish
