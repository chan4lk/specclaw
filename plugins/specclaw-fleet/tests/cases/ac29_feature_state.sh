#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
export SPECCLAW_DIR="$TMP/repo/.specclaw" FLEET_AZDO_ISSUE="$TMP/stub/specclaw-azdo-issue" AZDO_ORG=o AZDO_PROJECT=p AZDO_TOKEN=t WI="$TMP/wi" TMP
stub specclaw-azdo-issue '
d="$WI/$3"
case "$1" in
  show) [[ -f "$d/noread" ]] && exit 1; jq -nc --arg t "$(cat "$d/tags" 2>/dev/null)" "{fields: {\"System.Tags\": \$t, \"System.AssignedTo\": {uniqueName: \"alice@contoso.com\"}}}" ;;
  records) [[ -f "$d/recfail" ]] && exit 1; cat "$d/records" 2>/dev/null || echo "{\"records\":[]}" ;;
  updates) [[ "$(cat "$d/tags" 2>/dev/null)" == *fleet:auto* ]] && echo "{\"value\":[{\"revisedBy\":{\"uniqueName\":\"alice@contoso.com\"},\"fields\":{\"System.Tags\":{\"oldValue\":\"\",\"newValue\":\"fleet:auto\"}}}]}" || echo "{\"value\":[]}" ;;
esac'
stub curl 'f="$TMP/pr-$(grep -oE "pullrequests/[0-9]+" <<<"$*" | cut -d/ -f2).json"; [[ "$(cat "$f" 2>/dev/null)" == FAIL500 ]] && { printf "\n500"; exit 0; }
cat "$f" 2>/dev/null || echo "{}"; printf "\n200"'
mk() { mkdir -p "$SPECCLAW_DIR/changes/$1" "$WI/$1"; printf '**Feature:** cat\n**Depends on:** %s\n' "$2" > "$SPECCLAW_DIR/changes/$1/proposal.md"
  printf '**Azure Boards Work Item:** [#1](https://x)\n' > "$SPECCLAW_DIR/changes/$1/status.md"; printf '%s' "$3" > "$WI/$1/tags"; }
rec() { printf '{"records":[{"at":"2026-11-08T00:00:00Z","state":"%s","pr":"%s"}]}' "$2" "$3" > "$WI/$1/records"; }
pr() { printf '{"status":"%s","mergeStatus":"%s","targetRefName":"refs/heads/feature/%s"}' "$2" "$3" "$4" > "$TMP/pr-$1.json"; }
reset() { rm -rf "$TMP/repo" "$WI" "$TMP"/pr-*.json; mkdir -p "$SPECCLAW_DIR"; git -C "$TMP/repo" init -q; }
states() { (cd "$TMP/repo" && "$FLEET" feature plan cat --json) 2>/dev/null | jq -r '[.members[] | "\(.change)=\(.state)"] | join(" ")'; }
rows=1
row() { local got; got="$(states)"; [[ "$got" == "$1" ]] || { rows=0; echo "  want [$1] got [$got]"; }; }
reset; mk 002-a none "fleet:auto"; mk 003-b 002-a "fleet:auto"; mk 004-c 002-a ""
row "002-a=ready 003-b=waiting 004-c=not-opted-in"
rec 002-a pr_open https://x/pullrequest/11; pr 11 completed succeeded cat; row "002-a=merged 003-b=ready 004-c=not-opted-in"
pr 11 completed succeeded main; row "002-a=ready 003-b=waiting 004-c=not-opted-in"
pr 11 active conflicts cat; row "002-a=conflict 003-b=waiting 004-c=not-opted-in"
pr 11 active succeeded cat; row "002-a=pr_open 003-b=waiting 004-c=not-opted-in"
reset; mk 002-a none "fleet:auto; fleet:refused"; mk 003-b 002-a "fleet:auto"; mk 004-c 002-a "fleet:auto"
row "002-a=failed 003-b=waiting 004-c=waiting"
reset; mk 002-a none "fleet:auto"; rec 002-a failed ""; mk 003-b none "fleet:auto"; rec 003-b running ""; mk 004-c none "fleet:auto"; touch "$WI/004-c/noread"
row "002-a=failed 003-b=running 004-c=?"
reset; mk 002-a none "fleet:auto"; mk 003-b 002-a "fleet:auto"; mk 004-c none "fleet:auto"
echo '{"branch":"specclaw/002-a"}' > "$SPECCLAW_DIR/changes/002-a/state.json"
git -C "$TMP/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m a
git -C "$TMP/repo" update-ref refs/remotes/origin/specclaw/002-a HEAD; git -C "$TMP/repo" update-ref refs/remotes/origin/feature/cat HEAD
row "002-a=merged 004-c=ready 003-b=ready"
reset; mk 002-a none "fleet:auto; fleet:dispatched; fleet:conflict-retried"; mk 003-b 002-a "fleet:auto"; mk 004-c none "fleet:auto"
printf '{"records":[{"at":"2026-11-09T00:00:00Z","state":"running"},{"at":"2026-11-08T00:00:00Z","state":"pr_open","pr":"https://x/pullrequest/12"}]}' > "$WI/002-a/records"
pr 12 active conflicts cat; rec 004-c pr_open https://x/pullrequest/13
row "002-a=running 004-c=? 003-b=waiting"
cls=1
one() { local got; got="$(states)"; got="${got%% *}"; [[ "$got" == "002-a=$1" ]] || { cls=0; echo "  [$2] got $got want $1"; }; }
for body in '[]' '{"x":1}' 'FAIL500' ''; do
  reset; mk 002-a none "fleet:auto"; rec 002-a pr_open https://x/pullrequest/21; printf '%s' "$body" > "$TMP/pr-21.json"; one '?' "pr body [$body]"
done
for r in recfail junk noarray; do
  reset; mk 002-a none "fleet:auto"
  case "$r" in recfail) touch "$WI/002-a/recfail" ;; junk) echo "<html>" > "$WI/002-a/records" ;; noarray) echo '{"records":"x"}' > "$WI/002-a/records" ;; esac
  one '?' "records $r"
done
for st in dispatched running; do
  reset; mk 002-a none "fleet:auto"
  printf '{"records":[{"at":"2","state":"%s"},{"at":"1","state":"pr_open","pr":"https://x/pullrequest/22"}]}' "$st" > "$WI/002-a/records"
  pr 22 active conflicts cat; one running "newer $st over conflict"
  pr 22 completed succeeded cat; one merged "newer $st but PR merged"
done
reset; mk 002-a none "fleet:auto"; printf '{"records":[{"at":"1","state":"pr_open","pr":"https://x/pullrequest/23"}]}' > "$WI/002-a/records"
pr 23 active conflicts cat; one conflict "pr record newest"
states_ok() { (( rows == 1 && cls == 1 )); }
check "R050 AC-3 member state from PR status (completed into feature/<m> = merged, any merge type), conflicts, refusals, records, consent, deps; a merge by hand counts by ancestry; unreadable is ?; a newer dispatched/running record beats an older conflicting PR but never a merged one; any unreadable PR or records shape is ?" states_ok
finish
