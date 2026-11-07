# shellcheck shell=bash
prepare_workspace() {
  cp -a "$SEED/." "$HOME/" 2>/dev/null || true
  local heads ref b
  heads="$(git -C "$REPO" ls-remote --heads origin "refs/heads/*$FLEET_CHANGE")" \
    || { echo "could not list remote branches to look for an existing change branch" >&2; return 1; }
  ref="$(awk -v c="/$FLEET_CHANGE" 'substr($2, length($2) - length(c) + 1) == c { print $2; exit }' <<<"$heads")"
  [[ -n "$ref" ]] || return 0
  b="${ref#refs/heads/}"
  git -C "$REPO" fetch -q origin "$ref:refs/remotes/origin/$b" && git -C "$REPO" checkout -q -B "$b" "origin/$b" \
    || { echo "could not resume existing change branch $b" >&2; return 1; }
  echo "resuming existing change branch $b" >&2
}
