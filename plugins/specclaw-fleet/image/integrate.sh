# shellcheck shell=bash disable=SC2034
item_kind() { [[ "${FLEET_MODE:-}" == integrate ]] && echo features || echo changes; }

if [[ "${FLEET_MODE:-}" == integrate ]]; then
  PROMPT="Integrate feature $FLEET_CHANGE. This branch holds every member change of the feature, each already merged. Run the project's tests and the specclaw verify of each member change listed in .specclaw/features/$FLEET_CHANGE/proposal.md. Fix integration breakage with small commits; never rewrite or revert a member's work. Nobody is watching: never ask a question. Commit your fixes. Only when the project's tests and every member's verify pass, write the single word pass to .specclaw/features/$FLEET_CHANGE/integration-result and commit it; otherwise write fail. After you exit, this pod pushes the branch and opens the PR to ${SPECCLAW_PR_TARGET:-main}: ready for review only when that file says pass, a draft otherwise."
fi

merge_base_ref() {
  local b; b="$(change_branch)"
  [[ "${FLEET_MODE:-}" == integrate ]] && rm -f "$REPO/.specclaw/features/$FLEET_CHANGE/integration-result"
  if [[ "${FLEET_MODE:-}" == integrate && "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" != "$b" ]]; then git -C "$REPO" checkout -q -b "$b" || return 1; fi
  [[ -n "${FLEET_MERGE_REF:-}" ]] || return 0
  git -C "$REPO" fetch -q origin "refs/heads/$FLEET_MERGE_REF:refs/remotes/origin/$FLEET_MERGE_REF" || return 1
  git -C "$REPO" merge -q --no-edit "origin/$FLEET_MERGE_REF" >&2 && return 0
  [[ -n "$(git -C "$REPO" diff --name-only --diff-filter=U)" ]] || return 1
  PROMPT="The change branch has unresolved merge conflicts with $FLEET_MERGE_REF (git status shows them). Resolve them first, keeping both sides' intent, and commit the merge. Then: $PROMPT"
}

integration_passed() {
  [[ "$(tr -d '[:space:]' < "$REPO/.specclaw/features/$FLEET_CHANGE/integration-result" 2>/dev/null)" == pass ]]
}
