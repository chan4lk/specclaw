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
      | .platforms == "linux/amd64,linux/arm64" and .push == true and (.tags | startswith("ghcr.io/"))' <<<"$w" >/dev/null
}
hosted_ok() {
  local h; h="$(yq_py "$H")"
  jq -e '.pool == {"vmImage":"ubuntu-latest"} and (.variables.fleetSpecclawRef | length > 0) and (.variables.fleetImage | startswith("ghcr.io/"))' <<<"$h" >/dev/null \
    && grep -q 'git clone --quiet --depth 1 --branch "$(fleetSpecclawRef)"' "$H" \
    && grep -q 'task.prependpath\]$(Agent.TempDirectory)/specclaw/plugins/specclaw-fleet/bin' "$H" \
    && grep -q 'task.prependpath\]$(Agent.TempDirectory)/specclaw/plugins/specclaw-sync/bin' "$H"
}
same_script() {
  [[ "$(yq_py "$H" | jq -r '.steps[] | select(.task? == "AzureCLI@2") | .inputs.inlineScript')" \
    == "$(yq_py "$S" | jq -r '.steps[] | select(.task? == "AzureCLI@2") | .inputs.inlineScript')" ]] \
    && grep -q 'FLEET_CLAUDE_VERSION: $(fleetClaudeVersion)' "$H" && grep -q 'FLEET_CLAUDE_VERSION: $(fleetClaudeVersion)' "$S"
}

check "AC6 image workflow builds amd64+arm64, pushes to GHCR, grants only packages: write" workflow_ok
check "AC9 hosted template runs on ubuntu-latest and fetches specclaw at a pinned ref onto PATH" hosted_ok
check "AC9 hosted and self-hosted templates run the identical dispatch script and pass the claude version" same_script
finish
