#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
W="$FLEET_ROOT/../../.github/workflows/fleet-image.yml"

load() { (export SPECCLAW_DIR="$TMP/sc"; unset AZDO_ORG AZDO_PROJECT AZDO_TOKEN; source "$FLEET_ROOT/lib/common.sh"; load_azdo_env; echo "org=[${AZDO_ORG:-}] proj=[${AZDO_PROJECT:-}] tok=[${AZDO_TOKEN:-}]") 2>&1; }
mkdir -p "$TMP/sc"
printf 'export AZDO_ORG="BistecGlobal"\r\nAZDO_PROJECT='"'"'Product-Portal'"'"'\r\nAZDO_TOKEN=abc123 # note\n# AZDO_ORG=commented\n' > "$TMP/sc/.env"; good="$(load)"
printf 'AZDO_ORG=two words\nAZDO_PROJECT="unbalanced\n' > "$TMP/sc/.env"; bad="$(load)"
env_parsed() { [[ "$good" == *"org=[BistecGlobal] proj=[Product-Portal] tok=[abc123]"* ]]; }
env_refused() { [[ "$bad" == *"org=[] proj=[]"* ]] && [[ $(grep -c "ignored unparsable" <<<"$bad") == 2 ]]; }
check "AC8 .env loader handles export, quotes, CRLF, comments" env_parsed
check "AC8 .env loader warns on and ignores unparsable values" env_refused

python3 -c 'import sys,yaml; s=[x for x in yaml.safe_load(open(sys.argv[1]))["jobs"]["build"]["steps"] if x.get("id")=="tag"][0]; print(s["run"])' "$W" > "$TMP/guard.sh"
stub curl 'case "$*" in *ghcr.io/token*) [[ -n "${NO_TOKEN:-}" ]] && exit 22; echo "{\"token\":\"t\"}" ;; *manifests*) printf %s "$CODE" ;; esac'
guard() { env GITHUB_REF_NAME=fleet-v1.2.3 GITHUB_OUTPUT="$TMP/gho" GITHUB_ACTOR=a GH_TOKEN=x IMAGE=ghcr.io/o/specclaw-fleet "$@" bash "$TMP/guard.sh" > "$TMP/g.out" 2>&1; }
: > "$TMP/gho"; guard CODE=404; new_rc=$?; outputs="$(cat "$TMP/gho")"
verdicts=1
for c in 200 401 500 000; do guard CODE=$c && verdicts=0; done
guard NO_TOKEN=1 CODE=404 && verdicts=0
guard CODE=404 GITHUB_REF_NAME=fleet-vbad && verdicts=0
publishes_new() { (( new_rc == 0 )) && grep -q "tag=1.2.3" <<<"$outputs" && grep -q "codex=0.167.0" <<<"$outputs"; }
refuses_rest() { (( verdicts == 1 )); }
check "AC6 overwrite guard: a confirmed 404 proceeds with validated outputs" publishes_new
check "AC6 overwrite guard: existing tag, auth/server/network errors, no token and bad tags all fail" refuses_rest
finish
