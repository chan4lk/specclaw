# shellcheck shell=bash
prepare_workspace() {
  cp -a "$SEED/." "$HOME/" 2>/dev/null || true
  local ref
  ref="$(git -C "$REPO" ls-remote --heads origin "refs/heads/*$FLEET_CHANGE" | awk -v c="/$FLEET_CHANGE" 'substr($2, length($2) - length(c) + 1) == c { print $2; exit }')"
  [[ -n "$ref" ]] || return 0
  git -C "$REPO" fetch -q origin "$ref:refs/remotes/origin/${ref#refs/heads/}" \
    && git -C "$REPO" checkout -q -B "${ref#refs/heads/}" "origin/${ref#refs/heads/}" \
    && echo "resuming existing change branch ${ref#refs/heads/}" >&2
}
