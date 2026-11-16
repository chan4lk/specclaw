#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
export FLEET_PUSH_PAUSES=0 FLEET_PUSH_ATTEMPTS=1
B="$TMP/bundles" OLD=0123456789abcdef0123456789abcdef01234567
blog() { tr '\n' '|' 2>/dev/null < "$TMP/bundle.log"; }
seed() { rm -rf "$B"; mkdir -p "$B"; echo bundle > "$B/work.bundle"; printf '%s\n' "${1:-$OLD}" > "$B/work.base"; }
left() { ls "$B" 2>/dev/null | tr '\n' ' '; }

rm -rf "$B"; mkdir -p "$B"; echo stale > "$B/work.bundle"; PUSH_FAILS=9 AGENT_RC=5 run_entry
saved="$(cat "$CALLS")"; saved_exit="$(cat "$TMP/status/exit")"; saved_log="$(blog)"; saved_base="$(cat "$B/work.base" 2>/dev/null)"; saved_bundle="$(cat "$B/work.bundle" 2>/dev/null)"; saved_left="$(left)"
rm -rf "$B"; ENTRY_BUNDLES="" PUSH_FAILS=9 AGENT_RC=5 run_entry; none="$(cat "$CALLS")"; none_exit="$(cat "$TMP/status/exit")"
mkdir -p "$B"; ENTRY_BUNDLES="" PUSH_FAILS=9 AGENT_RC=5 run_entry; off_folder="$(cat "$CALLS")"; off_left="$(ls "$B")"
rm -rf "$B"; PUSH_FAILS=9 AGENT_RC=5 run_entry; lost="$(cat "$CALLS")"; lost_exit="$(cat "$TMP/status/exit")"
seed; BUNDLE_CREATE_FAIL=1 PUSH_FAILS=9 AGENT_RC=5 run_entry; keep_old="$(cat "$CALLS")"; keep_old_left="$(left)"
seed; BUNDLE_CREATE_FAIL=1 BUNDLE_BAD=1 PUSH_FAILS=9 AGENT_RC=5 run_entry; drop_old="$(cat "$CALLS")"; drop_old_left="$(left)"
seed; AGENT_RC=5 run_entry; ok_out="$(cat "$TMP/out")"; ok_log="$(blog)"; ok_left="$(left)"
seed; BUNDLE_BAD=1 PUSH_FAILS=9 AGENT_RC=5 run_entry; bad_out="$(cat "$TMP/out")"; bad_log="$(blog)"
seed; BUNDLE_NOT_ANCESTOR=$OLD PUSH_FAILS=9 AGENT_RC=5 run_entry; anc_out="$(cat "$TMP/out")"; anc_log="$(blog)"; anc_base="$(cat "$B/work.base")"
junk_rows=1
for junk in "--upload-pack=touch $TMP/pwned" "${OLD}0" "${OLD^^}" $'line1\nline2' "$(printf 'a%.0s' {1..5000})"; do
  seed "$junk"; PUSH_FAILS=9 AGENT_RC=5 run_entry; out="$(cat "$TMP/out")"
  grep -q "WARNING: saved bundle base in $B/work.base is not a commit id" <<<"$out" && ! grep -q "resuming from saved bundle" <<<"$out" \
    && ! grep -qF -e "upload-pack" -e "line1" -e "aaaaaaaa" <<<"$out$(cat "$CALLS")" && [[ "$(blog)" != *fetch* && ! -e "$TMP/pwned" ]] \
    || { junk_rows=0; echo "  base ${junk:0:20}: used or printed"; }
done
# Remote change branch plus a bundle: ahead fast-forwards, behind is already pushed, diverged keeps both.
rel_rows=1
for row in "ahead|resuming from saved bundle|FETCH_HEAD|" "behind||-|" "diverged|WARNING: saved bundle $B/work.bundle has diverged from the remote branch specclaw/049-x|-|work.base work.bundle "; do
  IFS='|' read -r rel msg co keep <<<"$row"
  seed; REMOTE_BRANCH=specclaw/049-x BUNDLE_REL=$rel BUNDLE_TIP=tip1 TIP_NOT_PUSHED=$([[ $rel == diverged ]] && echo 1) AGENT_RC=5 run_entry
  out="$(cat "$TMP/out")" calls="$(cat "$CALLS")"
  grep -q "resuming existing change branch specclaw/049-x" <<<"$out" || { rel_rows=0; echo "  $rel: remote branch not resumed"; }
  [[ -z "$msg" ]] || grep -qF "$msg" <<<"$out" || { rel_rows=0; echo "  $rel: no '$msg'"; }
  [[ -n "$msg" ]] || ! grep -q "saved bundle" <<<"$out" || { rel_rows=0; echo "  $rel: unexpected bundle message"; }
  { [[ "$co" == FETCH_HEAD ]] && grep -q "checkout -q -B specclaw/049-x FETCH_HEAD" <<<"$calls"; } \
    || { [[ "$co" == - ]] && ! grep -q "checkout -q -B specclaw/049-x FETCH_HEAD" <<<"$calls"; } || { rel_rows=0; echo "  $rel: checkout"; }
  [[ "$(left)" == "$keep" ]] || { rel_rows=0; echo "  $rel: left [$(left)] want [$keep]"; }
  [[ -n "$keep" ]] && ! grep -q "WARNING: kept $B/work.bundle" <<<"$out" && { rel_rows=0; echo "  $rel: kept without a warning"; }
done
# After a good push: contained or unreadable goes, a tip the push lacks stays.
seed; BUNDLE_TIP=tip1 TIP_NOT_PUSHED=1 BUNDLE_REL=ahead AGENT_RC=5 run_entry; lacks_left="$(left)"; lacks_out="$(cat "$TMP/out")"
seed; BUNDLE_BAD=1 AGENT_RC=5 run_entry; unreadable_left="$(left)"
seed; BUNDLE_TIP=tip1 AGENT_RC=5 run_entry; contained_left="$(left)"
if [[ "$(id -u)" == 0 ]]; then ro=skip; else
  seed; ro_dir="$B"; chmod a-w "$B"; PUSH_FAILS=9 AGENT_RC=5 run_entry; ro="$(cat "$CALLS")"; chmod u+w "$ro_dir"
fi

saves() {
  [[ "$saved_exit" == 4 && "$saved_base" == deadbeef && "$saved_bundle" == bundle && "$saved_log" == *"bundle create $B/work.bundle.tmp deadbeef..refs/heads/specclaw/049-x"* ]] \
    && [[ "$saved_left" == "work.base work.bundle " ]] && grep -q "exit=push-failed .*bundle=saved" <<<"$saved"
}
no_folder() {
  [[ "$none_exit" == 4 ]] && grep -q "bundle=off" <<<"$none" && ! grep -q "bundle=saved" <<<"$none" || return 1
  grep -q "bundle=off" <<<"$off_folder" && [[ -z "$off_left" ]] || return 1
  [[ "$lost_exit" == 4 ]] && grep -q "bundle=none" <<<"$lost" && ! grep -q "bundle=off" <<<"$lost" || return 1
  [[ "$ro" == skip ]] && { echo "  SKIP: read-only bundle folder (running as root, so the folder stays writable)"; return 0; }
  grep -q "bundle=none" <<<"$ro" && ! grep -q "bundle=saved" <<<"$ro" && grep -q "bundle=none" <<<"$keep_old"
}
failed_save() {
  grep -q "bundle=none" <<<"$keep_old" && [[ "$keep_old_left" == "work.base work.bundle " ]] \
    && grep -q "bundle=none" <<<"$drop_old" && [[ -z "$drop_old_left" ]]
}
resumes() { grep -q "resuming from saved bundle" <<<"$ok_out" && [[ "$ok_log" == "bundle verify $B/work.bundle |fetch $B/work.bundle refs/heads/specclaw/049-x|bundle list-heads $B/work.bundle |" ]]; }
corrupt() {
  grep -q "WARNING: saved bundle .* failed git bundle verify" <<<"$bad_out" && ! grep -q "resuming from saved bundle" <<<"$bad_out" \
    && [[ "$bad_log" != *fetch* ]] && grep -q "WARNING: saved bundle base in $B/work.base is not a commit id that is an ancestor" <<<"$anc_out" \
    && ! grep -q "resuming from saved bundle" <<<"$anc_out" && [[ "$anc_log" != *fetch* && "$anc_base" == deadbeef ]]
}
untrusted_base() { (( junk_rows == 1 )); }
remote_and_bundle() { (( rel_rows == 1 )); }
cleans() {
  [[ -z "$ok_left" && -z "$unreadable_left" && -z "$contained_left" && "$lacks_left" == "work.base work.bundle " ]] \
    && grep -q "WARNING: kept $B/work.bundle: it holds commits the pushed branch does not" <<<"$lacks_out"
}

check "AC7 a fully failed push writes work.bundle (base..branch) and work.base, replacing the old pair, and records bundle=saved, exit 4" saves
check "AC7 bundles not configured records bundle=off (folder or not); a configured claim with a missing or read-only folder records bundle=none; all exit 4" no_folder
check "AC7 a failed save records bundle=none, keeps an older pair that verifies and removes one that does not" failed_save
check "AC8 no remote branch and a valid bundle: verify, fetch into the change branch, print resuming from saved bundle" resumes
check "AC8 a corrupt bundle or a base that is not an ancestor is ignored with a warning and the run starts fresh" corrupt
check "AC8 a work.base that is not a full lower-case commit id (option, too long, upper case, multi-line, huge) is never used or printed" untrusted_base
check "AC8 remote branch plus bundle: ahead fast-forwards, behind is already pushed, diverged warns and keeps the bundle" remote_and_bundle
check "AC9 a good push removes the pair when it holds the bundle tip or the bundle is unreadable, and keeps it with a warning otherwise" cleans
finish
