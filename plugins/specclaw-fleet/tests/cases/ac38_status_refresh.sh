#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
STEP="$TMP/refresh.sh"
python3 -c "import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); print([s for s in d['jobs'][0]['steps'] if s.get('displayName') == 'Refresh STATUS.md on this branch'][0]['script'])" \
  "$FLEET_ROOT/pipelines/dispatch-hosted.yml" > "$STEP"
export GIT_CONFIG_GLOBAL=/dev/null SPECCLAW_STATUS_NO_PR=1 FLEET_TRUSTED_BRANCH=main
export PATH="$FLEET_ROOT/../specclaw/bin:$PATH"
rows=1

setup() {
  rm -rf "${TMP:?}/remote.git" "${TMP:?}/work"
  git init -q --bare "$TMP/remote.git"
  git init -q -b "$1" "$TMP/work" && mkdir -p "$TMP/work/.specclaw/changes"
  printf 'project:\n  name: "t"\n' > "$TMP/work/.specclaw/config.yaml"
  git -C "$TMP/work" add -A && git -C "$TMP/work" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$TMP/work" remote add origin "$TMP/remote.git" && git -C "$TMP/work" push -q origin "$1"
}
run_step() { (cd "$TMP/work" && BUILD_SOURCEBRANCH="refs/heads/$1" bash "$STEP") > "$TMP/out" 2>&1; }
remote_msg() { git -C "$TMP/remote.git" log -1 --format=%s "$1" 2>/dev/null; }

while IFS='|' read -r name branch mode want; do
  setup "$branch"
  [[ "$mode" == reject ]] && printf '#!/bin/sh\nexit 1\n' > "$TMP/remote.git/hooks/pre-receive" && chmod +x "$TMP/remote.git/hooks/pre-receive"
  rc=0; run_step "$branch" || rc=$?
  got="$(remote_msg "$branch")"; ok=1
  (( rc == 0 )) || ok=0
  case "$want" in
    pushed) [[ "$got" == "specclaw: refresh STATUS.md [skip ci]" ]] && git -C "$TMP/remote.git" show "$branch:.specclaw/STATUS.md" | grep -q Dashboard || ok=0 ;;
    untouched) [[ "$got" == init ]] || ok=0 ;;
  esac
  [[ "$mode" == reject ]] && { grep -q "task.logissue type=warning]STATUS.md not refreshed: push" "$TMP/out" || ok=0; }
  (( ok )) || { rows=0; echo "  [$name] rc=$rc remote=$got $(head -c 300 "$TMP/out")"; }
done <<'EOF'
feature branch: commits and pushes with [skip ci]|feature/cat||pushed
main: commits and pushes|main||pushed
change branch: does nothing|specclaw/012-x||untouched
claude branch: does nothing|claude/fix||untouched
push refused: warning, exit 0|feature/cat|reject|untouched
EOF
skip_ci_only() { grep -q '\[skip ci\]' "$STEP" && (( rows == 1 )); }
check "R057 AC-2 the hosted pipeline refreshes STATUS.md only on main/feature branches, commits it with [skip ci] and pushes; change branches are left alone; a refused push warns and exits 0" skip_ci_only
finish
