#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
mkdir -p "$TMP/sc" "$TMP/trusted"
printf '%s\n' 'fleet:' '  vault: kv-a' '  cluster_name: c' '  namespace: specclaw-fleet' '  image: "ghcr.io/o/specclaw-fleet:0.9.1"' '  claude_version: "2.1.319"' \
  '  default_agent: claude' '  deadline_minutes: 120' '  pipeline: specclaw-fleet' '  pipeline_file: azure-pipelines/specclaw-fleet.yml' > "$TMP/sc/config.yaml"
cp "$TMP/sc/config.yaml" "$TMP/trusted/config.yaml"
load() {
  env -u FLEET_VAULT -u FLEET_IMAGE -u FLEET_CLUSTER_NAME -u FLEET_NAMESPACE -u FLEET_CLAUDE_VERSION -u FLEET_DEFAULT_AGENT -u FLEET_DEADLINE_MINUTES -u FLEET_PIPELINE -u FLEET_PIPELINE_FILE FLEET_TRUSTED_CONFIG="$TMP/trusted/config.yaml" bash -c '
    set -euo pipefail; SPECCLAW_DIR="$1"; source "$2/lib/common.sh"; source "$2/lib/settings.sh"; load_fleet_settings 2>/dev/null
    echo "vault=[${FLEET_VAULT-unset}] image=[${FLEET_IMAGE-unset}]"' _ "$TMP/sc" "$FLEET_ROOT"
}
runs=1
for ((n = 0; n < 20; n++)); do
  out="$(load)"; rc=$?
  (( rc == 0 )) && [[ "$out" == "vault=[kv-a] image=[ghcr.io/o/specclaw-fleet:0.9.1]" ]] || { runs=0; echo "  run $n: rc=$rc out=[$out]"; break; }
done
mkdir -p "$TMP/repo/.specclaw/changes/002-a"
cp "$TMP/sc/config.yaml" "$TMP/repo/.specclaw/config.yaml"
printf '**Feature:** cat\n**Depends on:** none\n' > "$TMP/repo/.specclaw/changes/002-a/proposal.md"
plan="$(cd "$TMP/repo" && env -u FLEET_VAULT -u FLEET_IMAGE -u FLEET_CLUSTER_NAME -u FLEET_NAMESPACE -u FLEET_CLAUDE_VERSION -u FLEET_DEFAULT_AGENT -u FLEET_DEADLINE_MINUTES -u FLEET_PIPELINE -u FLEET_PIPELINE_FILE FLEET_TRUSTED_CONFIG="$TMP/trusted/config.yaml" "$FLEET" feature plan cat --json 2>/dev/null)"; plan_rc=$?
loads_ok() { (( runs == 1 )); }
plan_ok() { (( plan_rc != 141 )) && jq -e '.members | length == 1' <<<"$plan" >/dev/null 2>&1; }
check "R055 trusted-config check reads a full trusted fleet: block (secure key first, every key set and already exported), 20 times, without SIGPIPE (exit 141)" loads_ok
check "R055 feature plan runs end to end with FLEET_TRUSTED_CONFIG set" plan_ok
finish
