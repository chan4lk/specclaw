# shellcheck shell=bash
change_branch() {
  local b prefix
  b="$(jq -r '.branch // empty' "$STATE" 2>/dev/null)"
  if [[ -z "$b" ]]; then
    prefix="$(sed -nE 's/^[[:space:]]+branch_prefix:[[:space:]]*"?([^"#[:space:]]*)"?.*/\1/p' "$REPO/.specclaw/config.yaml" 2>/dev/null | head -n1)"
    b="${prefix:-specclaw/}$FLEET_CHANGE"
  fi
  printf '%s' "$b"
}

prepare_workspace() {
  cp -a "$SEED/." "$HOME/" 2>/dev/null || true
  local heads b
  b="$(change_branch)"
  heads="$(git -C "$REPO" ls-remote --heads origin "refs/heads/$b")" \
    || { echo "could not list remote branches to look for an existing change branch" >&2; return 1; }
  awk -v r="refs/heads/$b" '$2 == r { f = 1 } END { exit !f }' <<<"$heads" || return 0
  git -C "$REPO" fetch -q origin "refs/heads/$b:refs/remotes/origin/$b" && git -C "$REPO" checkout -q -B "$b" "origin/$b" \
    || { echo "could not resume existing change branch $b" >&2; return 1; }
  echo "resuming existing change branch $b" >&2
}
