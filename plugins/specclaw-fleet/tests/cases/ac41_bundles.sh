#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
export FLEET_PUSH_PAUSES=0 FLEET_PUSH_ATTEMPTS=1
B="$TMP/bundles"
blog() { tr '\n' '|' < "$TMP/bundle.log" 2>/dev/null; }
seed() { rm -rf "$B"; mkdir -p "$B"; echo bundle > "$B/work.bundle"; echo "${1:-oldbase}" > "$B/work.base"; }

rm -rf "$B"; mkdir -p "$B"; echo stale > "$B/work.bundle"; PUSH_FAILS=9 AGENT_RC=5 run_entry
saved="$(cat "$CALLS")"; saved_exit="$(cat "$TMP/status/exit")"; saved_log="$(blog)"; saved_base="$(cat "$B/work.base" 2>/dev/null)"; saved_bundle="$(cat "$B/work.bundle" 2>/dev/null)"
rm -rf "$B"; PUSH_FAILS=9 AGENT_RC=5 run_entry; none="$(cat "$CALLS")"; none_exit="$(cat "$TMP/status/exit")"
seed; AGENT_RC=5 run_entry; ok_out="$(cat "$TMP/out")"; ok_log="$(blog)"; ok_left="$(ls "$B")"
seed; BUNDLE_BAD=1 PUSH_FAILS=9 AGENT_RC=5 run_entry; bad_out="$(cat "$TMP/out")"; bad_log="$(blog)"
seed; BUNDLE_NOT_ANCESTOR=oldbase PUSH_FAILS=9 AGENT_RC=5 run_entry; anc_out="$(cat "$TMP/out")"; anc_log="$(blog)"; anc_base="$(cat "$B/work.base")"
seed; REMOTE_BRANCH=specclaw/049-x PUSH_FAILS=9 AGENT_RC=5 run_entry; rem_out="$(cat "$TMP/out")"; rem_log="$(blog)"
seed; ro_dir="$B"; chmod a-w "$B"; PUSH_FAILS=9 AGENT_RC=5 run_entry; ro="$(cat "$CALLS")"; chmod u+w "$ro_dir"

saves() {
  [[ "$saved_exit" == 4 && "$saved_base" == deadbeef && "$saved_bundle" == bundle && "$saved_log" == *"bundle create $B/work.bundle.tmp deadbeef..refs/heads/specclaw/049-x"* ]] \
    && [[ ! -e "$B/work.bundle.tmp" ]] && grep -q "exit=push-failed .*bundle=saved" <<<"$saved"
}
no_folder() { [[ "$none_exit" == 4 ]] && grep -q "bundle=none" <<<"$none" && grep -q "bundle=none" <<<"$ro" && ! grep -q "bundle=saved" <<<"$none$ro"; }
resumes() { grep -q "resuming from saved bundle" <<<"$ok_out" && [[ "$ok_log" == "bundle verify $B/work.bundle |fetch $B/work.bundle refs/heads/specclaw/049-x|" ]]; }
corrupt() {
  grep -q "WARNING: saved bundle .* failed git bundle verify" <<<"$bad_out" && ! grep -q "resuming from saved bundle" <<<"$bad_out" \
    && [[ "$bad_log" != *fetch* ]] && grep -q "WARNING: saved bundle base oldbase is not an ancestor" <<<"$anc_out" \
    && ! grep -q "resuming from saved bundle" <<<"$anc_out" && [[ "$anc_log" != *fetch* && "$anc_base" == deadbeef ]]
}
remote_wins() { grep -q "resuming existing change branch specclaw/049-x" <<<"$rem_out" && ! grep -q "saved bundle" <<<"$rem_out" && [[ "$rem_log" != *verify* ]]; }
cleans() { [[ -z "$ok_left" ]]; }

check "AC7 a fully failed push writes work.bundle (base..branch) and work.base, replacing the old pair, and records bundle=saved, exit 4" saves
check "AC7 no bundle folder, or a read-only one, records bundle=none and still exits 4" no_folder
check "AC8 no remote branch and a valid bundle: verify, fetch into the change branch, print resuming from saved bundle" resumes
check "AC8 a corrupt bundle or a base that is not an ancestor is ignored with a warning and the run starts fresh" corrupt
check "AC8 the remote change branch wins over a saved bundle" remote_wins
check "AC9 a good push removes work.bundle and work.base" cleans
finish
