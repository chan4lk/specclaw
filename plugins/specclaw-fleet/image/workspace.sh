# shellcheck shell=bash
change_branch() {
  local b prefix
  b="$(jq -r '.branch // empty' "$STATE" 2>/dev/null)"
  if [[ -z "$b" ]]; then
    prefix="$(sed -nE 's/^[[:space:]]+branch_prefix:[[:space:]]*"?([^"#[:space:]]*)"?.*/\1/p' "$REPO/.specclaw/config.yaml" 2>/dev/null | awk 'NR == 1')"
    b="${prefix:-specclaw/}$([[ "${FLEET_MODE:-}" == integrate ]] && echo integrate-)$FLEET_CHANGE"
  fi
  printf '%s' "$b"
}

# Resume order: remote change branch, else a saved bundle (FR-8) whose base is in this clone, else fresh.
prepare_workspace() {
  cp -a "$SEED/." "$HOME/" 2>/dev/null || true
  local heads b base d="${FLEET_BUNDLE_DIR:-/fleet/bundles}"
  b="$(change_branch)"
  # The clone's HEAD before any resume or merge: the commit this run's change branch starts from; save_bundle uses it.
  BUNDLE_BASE="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"; export BUNDLE_BASE
  heads="$(git -C "$REPO" ls-remote --heads origin "refs/heads/$b")" \
    || { echo "could not list remote branches to look for an existing change branch" >&2; return 1; }
  if awk -v r="refs/heads/$b" '$2 == r { f = 1 } END { exit !f }' <<<"$heads"; then
    git -C "$REPO" fetch -q origin "refs/heads/$b:refs/remotes/origin/$b" && git -C "$REPO" checkout -q -B "$b" "origin/$b" \
      || { echo "could not resume existing change branch $b" >&2; return 1; }
    echo "resuming existing change branch $b" >&2; return 0
  fi
  [[ -f "$d/work.bundle" ]] || return 0
  base="$(cat "$d/work.base" 2>/dev/null)"
  git -C "$REPO" bundle verify "$d/work.bundle" >/dev/null 2>&1 \
    || { echo "WARNING: saved bundle $d/work.bundle failed git bundle verify; ignoring it and starting fresh" >&2; return 0; }
  [[ -n "$base" ]] && git -C "$REPO" merge-base --is-ancestor "$base" HEAD 2>/dev/null \
    || { echo "WARNING: saved bundle base ${base:-<missing>} is not an ancestor of the cloned HEAD; ignoring it and starting fresh" >&2; return 0; }
  git -C "$REPO" fetch -q "$d/work.bundle" "refs/heads/$b" && git -C "$REPO" checkout -q -B "$b" FETCH_HEAD \
    || { echo "WARNING: could not fetch $b from saved bundle; ignoring it and starting fresh" >&2; return 0; }
  echo "resuming from saved bundle" >&2
}
