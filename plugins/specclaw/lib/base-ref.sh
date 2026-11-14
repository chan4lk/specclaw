# shellcheck shell=bash
# lib/base-ref.sh — the merge-base with the base branch, shared by hooks/done-guard and
# specclaw-verify size (change 060). Sourced, never executed: no top-level side effects.

# base_merge_base <root>
# The base is git.base_branch, else origin/HEAD, else main; origin/<base> is preferred over a
# local <base>, as in specclaw-check-staged. No network (no gh). Prints nothing when there is none.
base_merge_base() {
  local root="$1" base ref
  base="$(awk '/^[a-zA-Z_]/ { g = ($0 ~ /^git:/); next } g && /^  base_branch:/ { sub(/^  base_branch:[[:space:]]*/, ""); print; exit }' \
    "$root/.specclaw/config.yaml" 2>/dev/null | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//; s/^"(.*)"$/\1/'"; s/^'(.*)'$/\\1/" || true)"
  [ -n "$base" ] || base="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [ -n "$base" ] || base=main
  for ref in "origin/$base" "$base"; do
    if git -C "$root" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      git -C "$root" merge-base "$ref" HEAD 2>/dev/null || true
      return 0
    fi
  done
}
