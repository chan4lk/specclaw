# shellcheck shell=bash
# lib/base-ref.sh — the merge-base with the base branch, shared by hooks/done-guard and
# specclaw-verify size (change 060). Sourced, never executed: no top-level side effects.

# base_config_branch <config.yaml>
# git.base_branch by the same rules as hooks/core/base.ts (baseBranchFrom); both are tested against
# tests/fixtures/base-branch.tsv. The git: block runs until a column-0 line that is not blank and not a
# comment; any indent; a comment needs a space before its # (as yaml_val); one pair of quotes dropped.
base_config_branch() {
  awk '/^[^[:space:]#]/ { g = ($0 ~ /^git:/); next }
       g && /^[[:space:]]+base_branch:/ { sub(/^[[:space:]]+base_branch:/, ""); print; exit }' "$1" 2>/dev/null \
    | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^"(.*)"$/\1/'"; s/^'(.*)'$/\\1/" || true
}

# base_merge_base <root>
# The base is git.base_branch, else origin/HEAD, else main; origin/<base> is preferred over a
# local <base>, as in specclaw-check-staged. No network (no gh). Prints "<merge-base sha> <ref>",
# "- <ref>" when the ref exists but has no merge-base with HEAD (a shallow clone), or nothing when
# there is no base ref.
base_merge_base() {
  local root="$1" base ref sha
  base="$(base_config_branch "$root/.specclaw/config.yaml")"
  [ -n "$base" ] || base="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [ -n "$base" ] || base=main
  for ref in "origin/$base" "$base"; do
    if git -C "$root" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
      sha="$(git -C "$root" merge-base "$ref" HEAD 2>/dev/null)" || sha=-
      printf '%s %s\n' "$sha" "$ref"
      return 0
    fi
  done
}
