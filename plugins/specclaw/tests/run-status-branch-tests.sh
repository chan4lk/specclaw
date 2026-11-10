#!/usr/bin/env bash
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/specclaw-update-status"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
export SPECCLAW_STATUS_NO_PR=1 GIT_CONFIG_GLOBAL=/dev/null
fail=0

repo() {
  local d="$TMP/$1"
  mkdir -p "$d/.specclaw/changes"
  printf 'project:\n  name: "t"\ngit:\n  base_branch: develop\n' > "$d/.specclaw/config.yaml"
  [[ "$2" == nogit ]] && { echo "$d"; return; }
  git -C "$d" init -q -b develop && echo committed > "$d/.specclaw/STATUS.md"
  git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm init
  case "$2" in detached) git -C "$d" checkout -q --detach ;; develop) ;; *) git -C "$d" checkout -q -b "$2" ;; esac
  echo "$d"
}

while IFS='|' read -r name branch flag want; do
  d="$(repo "$name" "$branch")"
  out="$(cd "$d" && "$BIN" $flag .specclaw 2>&1)"
  case "$want" in
    tracked) wantpath=".specclaw/STATUS.md"; file="$d/$wantpath" ;;
    local) wantpath="$(git -C "$d" rev-parse --path-format=absolute --git-path specclaw-STATUS.md)"; file="$wantpath" ;;
  esac
  ok=1
  grep -q "^OK: Updated $wantpath$" <<<"$out" && grep -q "SpecClaw Dashboard" "$file" || ok=0
  if [[ "$want" == local ]]; then
    [[ "$(cat "$d/.specclaw/STATUS.md")" == committed ]] || ok=0
    [[ -z "$(git -C "$d" status --porcelain)" ]] || ok=0
  fi
  (( ok )) && echo "PASS: $name" || { fail=1; echo "FAIL: $name: $out"; }
done <<'EOF'
base branch from config writes the tracked file|develop||tracked
main writes the tracked file|main||tracked
master writes the tracked file|master||tracked
feature branch writes the tracked file|feature/cat||tracked
change branch writes inside .git, tracked file and tree untouched|specclaw/012-x||local
claude branch writes inside .git|claude/fix||local
detached HEAD writes inside .git|detached||local
--integration on a change branch writes the tracked file|specclaw/013-y|--integration|tracked
outside git writes the tracked file|nogit||tracked
EOF
(( fail == 0 )) && echo "R057 AC-1 STATUS.md is written only on integration branches, --integration, or outside git; elsewhere inside .git"
exit "$fail"
