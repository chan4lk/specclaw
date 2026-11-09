# shellcheck shell=bash
feature_doc() {
  local d="$SPECCLAW_DIR/changes/$1"
  if [[ -f "$d/proposal.md" ]]; then printf '%s' "$d/proposal.md"; else printf '%s' "$d/change.md"; fi
}

doc_field() {
  sed -nE "s/^\*\*$2:\*\*[[:space:]]*(.*)$/\1/p" "$1" 2>/dev/null | head -n1 | sed -E 's/[[:space:]]+$//'
}

feature_members() {
  local d c
  for d in "$SPECCLAW_DIR"/changes/*/; do
    c="$(basename "$d")"
    [[ "$(doc_field "$(feature_doc "$c")" Feature)" == "$1" ]] && printf '%s\n' "$c"
  done
  return 0
}

change_deps() {
  local raw; raw="$(doc_field "$(feature_doc "$1")" "Depends on")"
  [[ -z "$raw" || "$(lower "$raw")" == none ]] && return 0
  tr ',' '\n' <<<"$raw" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; /^$/d'
}

feature_waves() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "feature module '$1' must match ^[a-z0-9][a-z0-9-]{0,40}$"
  local -a members=() left=() next=()
  local c d done=" " wave=0 ok
  mapfile -t members < <(feature_members "$1")
  (( ${#members[@]} )) || die "feature $1 has no members (no change declares **Feature:** $1)"
  for c in "${members[@]}"; do
    while IFS= read -r d; do
      [[ " ${members[*]} " == *" $d "* ]] || die "$c depends on $d, which is not a member of feature $1"
    done < <(change_deps "$c")
  done
  left=("${members[@]}")
  while (( ${#left[@]} )); do
    wave=$((wave + 1)); next=(); local -a ready=()
    for c in "${left[@]}"; do
      ok=1; while IFS= read -r d; do [[ "$done" == *" $d "* ]] || ok=0; done < <(change_deps "$c")
      if (( ok )); then ready+=("$c"); else next+=("$c"); fi
    done
    (( ${#ready[@]} )) || die "feature $1 has a dependency cycle among: ${left[*]}"
    for c in "${ready[@]}"; do printf '%s\t%s\n' "$wave" "$c"; done
    for c in "${ready[@]}"; do done+="$c "; done
    left=(${next[@]+"${next[@]}"})
  done
}
