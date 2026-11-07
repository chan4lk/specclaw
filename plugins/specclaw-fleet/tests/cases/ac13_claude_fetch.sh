#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/entry-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/entry-env.sh"
D="$FLEET_ROOT/image/Dockerfile"

fetch() {
  rm -rf "${TMP:?}/fh" && mkdir -p "$TMP/fh"
  (export HOME="$TMP/fh" FLEET_CLAUDE_VERSION="${1:-9.9.9}"; source "$FLEET_ROOT/image/claude-fetch.sh"; fetch_claude && echo "secs=$FLEET_CLAUDE_FETCH_S") > "$TMP/fetch.out" 2>&1
}

make_release "real-binary-bytes"; fetch; ok_rc=$?
installed() { (( ok_rc == 0 )) && [[ "$(cat "$TMP/fh/.fleet/bin/claude")" == real-binary-bytes && -x "$TMP/fh/.fleet/bin/claude" ]] && grep -q "^secs=[0-9]" "$TMP/fetch.out"; }
check "AC2 verified release installs the pinned binary and times the fetch" installed

refused_all=1
for mode in tampered impostor badsum badsize noplat rollback; do
  make_release "real-binary-bytes" "$mode"; fetch
  (( $? != 0 )) && [[ ! -e "$TMP/fh/.fleet/bin/claude" && ! -e "$TMP/fh/.fleet/bin/claude.part" ]] || { refused_all=0; echo "  accepted: $mode"; }
done
make_release "real-binary-bytes"; fetch '9.9.9/../evil'; (( $? != 0 )) || refused_all=0
refuses() { (( refused_all == 1 )); }
check "AC3 tampered, wrong-key, bad-checksum, bad-size, missing-platform, rolled-back and bad-version releases are refused" refuses

make_release "x" impostor; GATE="" run_entry; bad_calls="$(cat "$CALLS")"
make_release "#!/bin/sh"; GATE="" run_entry; good_calls="$(cat "$CALLS")"
rm -rf "$TMP/releases"; GATE="" run_entry; gone_calls="$(cat "$CALLS")"; make_release "#!/bin/sh"
pod_level() {
  grep -q "state=failed exit=claude-verify-failed" <<<"$bad_calls" && ! grep -q "state=running" <<<"$bad_calls" \
    && grep -q "state=running .*claude_fetch_s=[0-9]" <<<"$good_calls" \
    && grep -q "state=failed exit=claude-fetch-failed" <<<"$gone_calls"
}
check "AC2/AC3 the pod refuses to run an unverified claude and records fetch time otherwise" pod_level

image_clean() {
  ! sed -n '/^FROM node/,$p' "$D" | grep -q "claude-code-releases" && grep -q "DISABLE_UPDATES=1" "$D" \
    && grep -q "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE" "$D" && grep -q "COPY --from=seed" "$D" \
    && sed -n '1,/^FROM node/p' "$D" | grep -q "fetch_claude"
}
check "AC1 final stage has no claude, the seed stage verifies its download, key pinned, updates blocked" image_clean
per_run() { grep -q "fix rounds in this run" "$FLEET_ROOT/image/entrypoint.sh"; }
check "AC5 the review budget is per run" per_run
finish
