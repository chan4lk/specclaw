#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
W="$FLEET_ROOT/../../.github/workflows/fleet-image.yml"
H="$FLEET_ROOT/pipelines/dispatch-hosted.yml"
S="$FLEET_ROOT/pipelines/dispatch.yml"
yq_py() { python3 -c "import sys,yaml,json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$1"; }

workflow_ok() {
  local w; w="$(yq_py "$W")"
  jq -e '.permissions == {"contents":"read","packages":"write"}' <<<"$w" >/dev/null \
    && jq -e '(.on.push.tags // .true.push.tags) == ["fleet-v*"]' <<<"$w" >/dev/null \
    && jq -e '[.jobs.build.steps[] | select(.uses? // "" | startswith("docker/build-push-action"))][0].with
      | .platforms == "linux/amd64,linux/arm64" and .push == true and (.tags | startswith("ghcr.io/"))' <<<"$w" >/dev/null \
    && jq -e '[.jobs.build.steps[] | .uses? // empty | test("@[0-9a-f]{40}$")] | all' <<<"$w" >/dev/null \
    && jq -e '.jobs.build.if | contains("refs/heads/main") and contains("refs/tags/fleet-v")' <<<"$w" >/dev/null \
    && grep -q 'already exists' "$W" && grep -q 'bad tag' "$W"
}
hosted_ok() {
  local h; h="$(yq_py "$H")"
  jq -e '.pool == {"vmImage":"ubuntu-latest"} and (.variables.fleetSpecclawRef | length > 0)' <<<"$h" >/dev/null \
    && grep -q '\^\[0-9a-f\]{40}\$' "$H" && grep -q 'rev-parse HEAD)" == "$ref"' "$H" \
    && grep -q 'task.prependpath\]$(Agent.TempDirectory)/specclaw/plugins/specclaw-fleet/bin' "$H" \
    && grep -q 'task.prependpath\]$(Agent.TempDirectory)/specclaw/plugins/specclaw-sync/bin' "$H"
}
same_script() {
  [[ "$(yq_py "$H" | jq -r '.steps[] | select(.task? == "AzureCLI@2") | .inputs.inlineScript')" \
    == "$(yq_py "$S" | jq -r '.steps[] | select(.task? == "AzureCLI@2") | .inputs.inlineScript')" ]] \
    && grep -q 'export FLEET_KUBE_CONTEXT=$' "$H"
}

check "AC6 image workflow: amd64+arm64 to GHCR, packages: write only, SHA-pinned actions, validated tags, no overwrite" workflow_ok
check "AC9 hosted template runs on ubuntu-latest and fetches specclaw at a verified full commit SHA onto PATH" hosted_ok
check "AC9 hosted and self-hosted templates run the identical dispatch script, which uses the logged-in kubeconfig" same_script
no_settings() {
  [[ "$(yq_py "$H" | jq -r '.variables | keys | sort | join(",")')" == fleetAzureConnection,fleetKubeConnection,fleetSpecclawRef ]] || return 1
  [[ "$(yq_py "$S" | jq -r '.variables | keys | sort | join(",")')" == fleetAzureConnection,fleetKubeConnection ]] || return 1
  local t; for t in "$H" "$S"; do
    ! grep -Eq 'FLEET_(VAULT|IMAGE|NAMESPACE|DEADLINE_MINUTES|DEFAULT_AGENT|CLAUDE_VERSION):' "$t" || return 1
  done
}
check "R053 AC-2 templates keep only the compile-time names; every other setting comes from fleet: config" no_settings
finish
