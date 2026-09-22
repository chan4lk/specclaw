#!/usr/bin/env bash
# run-prototype-byte-identity-tests.sh — PD-02: a project that did not decide
# SQ-013 REINTERPRET must be unable to tell this feature was ever added.
#
# WHY THIS IS TESTED BY DIFFING AGAINST main RATHER THAN BY ASSERTION. The
# prototype stage touches four shipped commands — bf-bootstrap, bf-ui,
# bf-rebuild-collect and (as prose) propose. Asserting "the FAITHFUL path still
# works" would pass while a stray warning, a reordered field or a changed exit
# code quietly altered what every existing brownfield project sees. The only
# honest check is to run the OLD binary and the NEW one over the same fixture
# and compare bytes, so this suite does exactly that.
#
# The promise being kept is concrete: a rebuild that answered FAITHFUL,
# THEME-ONLY, or has not answered SQ-013 at all pays nothing for a stage it
# never runs — not a line of output, not an exit code, not a warning.
#
# The one deliberate exception, stated rather than hidden: the standard
# question bank gained SQ-015 (frontend language) and its version went 2 -> 3.
# That changes what /specclaw:bf-clarify offers in EVERY brownfield repo, by
# design and with approval, so bf-clarify is out of scope for this comparison.
# SQ-015 is applicable only under REINTERPRET, so a FAITHFUL project sees it
# marked not-applicable rather than asked.
#
# Skips cleanly when a `main` ref is not available (shallow CI checkouts), so
# it can never fail for a reason unrelated to what it tests.
#
# Bash + coreutils + git + jq.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "$2" | head -12; }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype byte-identity suite (exit 0)."; exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git not available — skipping prototype byte-identity suite (exit 0)."; exit 0
fi

BASE=""
for ref in main origin/main; do
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then BASE="$ref"; break; fi
done
if [ -z "$BASE" ]; then
  echo "no main/origin/main ref in this checkout (shallow clone?) — skipping prototype byte-identity suite (exit 0)."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Materialise the WHOLE plugin tree at the base ref, not just the binaries.
# Two reasons. First, these scripts derive their plugin root from their own
# location and read templates and references relative to it — a loose binary in
# a temp directory resolves a different root and reports a different plugin
# version, which would look like a regression and is not. Second, comparing
# whole trees means a change to a shared template is caught too, which a
# binaries-only comparison would miss entirely.
OLD_TREE="$WORK/oldtree"; mkdir -p "$OLD_TREE"
if ! git -C "$REPO_ROOT" archive "$BASE" plugins/specclaw 2>/dev/null | tar -x -C "$OLD_TREE" 2>/dev/null; then
  echo "could not materialise plugins/specclaw at ${BASE} — skipping suite (exit 0)."; exit 0
fi
OLD_PLUGIN="$OLD_TREE/plugins/specclaw"
[ -d "$OLD_PLUGIN/bin" ] || { echo "no bin/ in the ${BASE} tree — skipping suite (exit 0)."; exit 0; }
chmod +x "$OLD_PLUGIN"/bin/specclaw-* 2>/dev/null || true

DECISIONS_HEAD='# Decisions

## Decisions

### SQ-001 — Target platform

- **Decision:** Web application

### SQ-002 — Database engine and hosting

- **Decision:** Managed Postgres

### SQ-003 — Hosting/deployment model

- **Decision:** Containers

### SQ-004 — Authentication/authorization approach

- **Decision:** OIDC

### SQ-006 — UI framework / component library

- **Decision:** Kestrelize (Runescript)
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10

### SQ-014 — Target backend stack

- **Decision:** Kestrel API'

# One fixture repo, at a given policy. Built at a FIXED path so nothing
# path-dependent in the output can masquerade as a difference.
build_repo() {
  local R="$1" policy="$2"
  rm -rf "$R"; mkdir -p "$R/.specclaw/analysis" "$R/.specclaw/ui" "$R/.specclaw/changes/003-work-order-list"
  printf 'version: 1\n' > "$R/.specclaw/config.yaml"
  { printf '%s\n' "$DECISIONS_HEAD"
    if [ "$policy" != "UNDECIDED" ]; then
      printf '\n### SQ-013 — UI fidelity policy\n\n- **Decision:** %s — the recorded policy.\n- **Decided by:** Dana Okafor\n- **Date:** 2026-09-10\n' "$policy"
    fi
  } > "$R/.specclaw/analysis/decisions.md"
  cat > "$R/.specclaw/analysis/target-architecture.md" <<'ARCH'
# Target Architecture

## Legacy-to-target mapping

| Legacy element | Target element | Sanctioning decision | Status |
|---|---|---|---|
| Legacy shell | Kestrelize (Runescript) | SQ-006 | DECIDED |
ARCH
  cat > "$R/.specclaw/analysis/rebuild-backlog.md" <<'BL'
# Rebuild Backlog

## MOD-002 — Work orders

### BL-014 — Work order list

Acceptance basis cites SCR-001 and DR-021.
BL
  printf '# UI Inventory\n\n### SCR-001 — Work order list\n\nShows DR-021.\n\n### SCR-002 — Detail\n\nShows DR-022.\n' > "$R/.specclaw/ui/ui-inventory.md"
  printf '{"token_groups":[]}' > "$R/.specclaw/ui/design-tokens.json"
  printf '# Proposal: Work order list\n\nImplements item BL-014.\n' > "$R/.specclaw/changes/003-work-order-list/proposal.md"
  cat > "$R/draft.txt" <<'DRAFT'
## MOD-002 — Work orders

### BL-014 — Work order list

Renders the list. Acceptance basis cites SCR-001 and DR-021.

SCREEN-BEARING: BL-014 | SCR-001 | renders the work order list
SCR-OUT-OF-SCOPE: SCR-002 | dropped from the rebuild
DRAFT
}

# Run one command with the old binary and the new one, at the same path, and
# compare stdout+stderr+exit code, plus any file it wrote.
compare() {
  local label="$1" policy="$2" bin="$3"; shift 3
  local R="$WORK/fixture"

  build_repo "$R" "$policy"
  local a_out a_files
  a_out="$( cd "$R" && bash "$OLD_PLUGIN/bin/$bin" "$@" 2>&1; printf 'rc=%s' "$?" )"
  a_files="$( cd "$R" && find .specclaw -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )"

  build_repo "$R" "$policy"
  local b_out b_files
  b_out="$( cd "$R" && bash "$PLUGIN_ROOT/bin/$bin" "$@" 2>&1; printf 'rc=%s' "$?" )"
  b_files="$( cd "$R" && find .specclaw -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort )"

  if [ "$a_out" = "$b_out" ] && [ "$a_files" = "$b_files" ]; then
    ok "$policy — $label: output, exit code and written files all identical"
  else
    bad "$policy — $label" "$(diff <(printf '%s\n' "$a_out") <(printf '%s\n' "$b_out") 2>/dev/null; diff <(printf '%s\n' "$a_files") <(printf '%s\n' "$b_files") 2>/dev/null)"
  fi
}

echo "== Every command a non-REINTERPRET project runs, old binary vs new =="

for policy in FAITHFUL THEME-ONLY UNDECIDED; do
  compare "bf-bootstrap collect"       "$policy" specclaw-bf-bootstrap      collect .specclaw
  compare "bf-bootstrap foundation-check" "$policy" specclaw-bf-bootstrap   foundation-check .specclaw
  compare "bf-ui --checklist"          "$policy" specclaw-bf-ui             checklist-collect .specclaw 003-work-order-list
  compare "bf-rebuild-collect collect" "$policy" specclaw-bf-rebuild-collect collect .specclaw
  compare "bf-rebuild-collect render"  "$policy" specclaw-bf-rebuild-collect render .specclaw draft.txt
done

echo
echo "== And the absence of .specclaw/prototype/ is itself invisible =="

# A non-REINTERPRET repo never grows the directory, so nothing can key off it.
R="$WORK/fixture"; build_repo "$R" FAITHFUL
( cd "$R" && bash "$PLUGIN_ROOT/bin/specclaw-bf-bootstrap" collect .specclaw >/dev/null 2>&1
  bash "$PLUGIN_ROOT/bin/specclaw-bf-rebuild-collect" render .specclaw draft.txt >/dev/null 2>&1 ) || true
if [ -e "$R/.specclaw/prototype" ]; then
  bad "no .specclaw/prototype/ is created in a FAITHFUL repo" "the directory was created"
else
  ok "no .specclaw/prototype/ is created in a FAITHFUL repo"
fi

echo
echo "prototype byte-identity suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
