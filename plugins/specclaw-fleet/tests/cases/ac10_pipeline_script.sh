#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
REAL_GIT="$(command -v git)"
stub specclaw-fleet 'exit 0'
stub git '[[ -n "${GIT_SHOW_FAIL:-}" && "$1" == show ]] && { echo "fatal: unable to read object" >&2; exit 128; }
exec "$REAL_GIT" "$@"'
export AGENT_TEMPDIRECTORY="$TMP" SYSTEM_COLLECTIONURI=https://dev.azure.com/o/ REAL_GIT
sed -n '/inlineScript: |/,/^    env:/p' "$FLEET_ROOT/pipelines/dispatch.yml" | sed '1d;$d;s/^        //' \
  | sed 's/\${{ parameters.vault }}/kv/' > "$TMP/step.sh"
OK='{"phases":{"proposal":{"status":"approved"}}}'
DRAFT='{"phases":{"proposal":{"status":"draft"}}}'
EDITED='{"phases":{"proposal":{"status":"approved"},"plan":{"status":"done"}}}'

put_state() {
  if [[ "$1" == - ]]; then rm -f "$TMP/r/s/state.json"; else printf '%s' "$1" > "$TMP/r/s/state.json"; fi
  git -C "$TMP/r" add -A && git -C "$TMP/r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m step
}

scenario() {
  local before="$1" after="$2" expect="$3" label="$4"
  rm -rf "$TMP/r" && mkdir -p "$TMP/r/.specclaw/changes/049-x" && git -C "$TMP/r" init -q
  ln -s .specclaw/changes/049-x "$TMP/r/s"
  put_state "$before" && put_state "$after"
  : > "$CALLS"
  (cd "$TMP/r" && bash "$TMP/step.sh") > "$TMP/out" 2>&1
  local rc=$? got=skip
  grep -q "specclaw-fleet dispatch 049-x --vault kv" "$CALLS" && got=dispatch
  (( rc != 0 )) && got=error
  outcome() { [[ "$got" == "$expect" ]]; }
  check "FR10 $label → $expect" outcome
}

scenario "$DRAFT" "$OK" dispatch "draft to approved"
scenario - "$OK" dispatch "added already approved"
scenario "$OK" "$EDITED" skip "approved to approved edit"
scenario "$OK" - skip "deleted"
scenario "$DRAFT" '{"phases":{' error "truncated at HEAD"
scenario "$DRAFT" '[]' error "array at HEAD"
scenario "$DRAFT" '"x"' error "string at HEAD"
scenario '{"phases"' "$OK" error "truncated at HEAD^1"
GIT_SHOW_FAIL=1 scenario "$DRAFT" "$OK" error "git cannot read the object"
rm -rf "$TMP/r" && mkdir -p "$TMP/r" && git -C "$TMP/r" init -q
git -C "$TMP/r" -c user.name=t -c user.email=t@t commit -q --allow-empty -m solo
(cd "$TMP/r" && bash "$TMP/step.sh") > "$TMP/out" 2>&1; solo_rc=$?
no_parent_fails() { (( solo_rc != 0 )) && grep -q "could not list changed state files" "$TMP/out"; }
check "FR10 no parent commit fails the step" no_parent_fails
finish
