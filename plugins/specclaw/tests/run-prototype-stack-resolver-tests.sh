#!/usr/bin/env bash
# run-prototype-stack-resolver-tests.sh — regression suite for PD-03a, the
# frontend-stack resolver /specclaw:bf-prototype runs before anything else.
#
# The rule this suite defends: a prototype is built in the framework AND the
# language the project actually decided, and NEITHER is ever defaulted. The
# expensive failure it exists to prevent is the quiet one — a rebuild that
# picked a framework, said nothing about a language, and got whichever language
# the framework's convention implies. Nobody decided that, so nobody approved
# the design that came out of it.
#
# The resolver is STACK-BLIND: it holds no list of frameworks and no list of
# languages, and it never infers one from the other. That is why every case
# below uses values the resolver cannot possibly recognise as well as ones it
# might — a resolver that "knows" a framework would pass the first and fail the
# second, and the two invented-stack cases at the end are what catch it.
#
# Tested through `collect`, the public entry point, rather than by sourcing the
# resolver: what matters is that the COMMAND stops, not that a function returns.
#
# Bash + coreutils + jq.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_BIN="$PLUGIN_ROOT/bin/specclaw-bf-prototype"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ $# -gt 1 ] && echo "         $2"; }

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" = "$actual" ]; then ok "$label"
  else bad "$label" "expected [$expected], got [$actual]"; fi
}
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) ok "$label" ;;
    *) bad "$label" "missing [$needle] in: $(printf '%s' "$haystack" | head -3)" ;; esac
}
assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  case "$haystack" in *"$needle"*) bad "$label" "unexpectedly found [$needle]" ;;
    *) ok "$label" ;; esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not installed — skipping prototype stack-resolver suite (exit 0)."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Fixture: the minimum a REINTERPRET repo needs for collect to reach the
# resolver. Only decisions.md and target-architecture.md vary per case. ──────
SQ013_BLOCK='### SQ-013 — UI fidelity policy

- **Family:** Standard bank
- **Decision:** REINTERPRET — new design; the legacy UI is reference material only.
- **Decided by:** Dana Okafor
- **Date:** 2026-09-10
'

make_repo() {
  local dir="$1" decisions_body="$2" arch_rows="${3:-}"
  rm -rf "$dir"
  mkdir -p "$dir/.specclaw/analysis" "$dir/.specclaw/ui"
  printf 'version: 1\nprototype:\n  skill: "some-prototype-skill"\n  output_dir: .specclaw/prototype/app/\n' \
    > "$dir/.specclaw/config.yaml"
  {
    printf '# Decisions\n\n## Decisions\n\n'
    printf '%s\n' "$SQ013_BLOCK"
    printf '%s\n' "$decisions_body"
  } > "$dir/.specclaw/analysis/decisions.md"
  {
    printf '# Target Architecture\n\n## Legacy-to-target mapping\n\n'
    printf '| Legacy element | Target element | Sanctioning decision | Status |\n'
    printf '|---|---|---|---|\n'
    [ -n "$arch_rows" ] && printf '%s\n' "$arch_rows"
  } > "$dir/.specclaw/analysis/target-architecture.md"
  printf '# UI Inventory\n\n### SCR-001 — Main list\n\nShows DR-001.\n' > "$dir/.specclaw/ui/ui-inventory.md"
  printf '# Rebuild Backlog\n\n## MOD-001 — Core\n\n### BL-001 — Main list\n\nCites SCR-001 and DR-001.\n' \
    > "$dir/.specclaw/analysis/rebuild-backlog.md"
}

# Framework question block with the given answer text.
fw_block() { printf '### SQ-006 — UI framework / component library\n\n- **Family:** Standard bank\n- **Decision:** %s\n- **Decided by:** Dana Okafor\n- **Date:** 2026-09-10\n' "$1"; }
# Language question block (SQ-015) with the given answer text.
lang_block() { printf '### SQ-015 — Target frontend language\n\n- **Family:** Standard bank\n- **Decision:** %s\n- **Decided by:** Priya Raman\n- **Date:** 2026-09-12\n' "$1"; }

collect_out() { bash "$PROTO_BIN" collect "$1/.specclaw" 2>&1; }
collect_json() { bash "$PROTO_BIN" collect "$1/.specclaw" 2>/dev/null; }

echo "== PD-03a — framework and language, both provable, neither defaulted =="

# ── 1. Framework decided, language silent. THE headline case. ───────────────
make_repo "$WORK/a" "$(fw_block 'Kestrelize')"
OUT="$(collect_out "$WORK/a")"; RC=$?
assert_eq "1" "$RC" "framework decided but language silent: collect exits non-zero"
assert_contains "$OUT" "language: no decided SQ/CQ names the frontend language" \
  "…and names the language as the missing value, not the framework"
assert_contains "$OUT" "NEVER defaulted" "…and says the language is never defaulted"
assert_contains "$OUT" "/specclaw:bf-clarify" "…and names the route that fixes it"
assert_contains "$OUT" "Nothing was written" "…and states that nothing was written"

# ── 2. Both in one answer, one citation (PD-04's combined form). ────────────
make_repo "$WORK/b" "$(fw_block 'Kestrelize (Runescript)')"
J="$(collect_json "$WORK/b")"
assert_eq "Kestrelize (Runescript)" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" \
  "combined answer: framework value is the decision text verbatim"
assert_eq "Runescript" "$(printf '%s' "$J" | jq -r '.stack.language.value')" \
  "combined answer: language read from the single-word parenthetical"
assert_eq "SQ-006" "$(printf '%s' "$J" | jq -r '.stack.language.sanctioned_by')" \
  "combined answer: language cites the SAME question that decided the framework"

# ── 3. A multi-word parenthetical is NOT a language. Telling a language from
# a build tool would need the list this resolver refuses to hold, so it takes
# neither rather than guessing. ────────────────────────────────────────────
make_repo "$WORK/c" "$(fw_block 'Kestrelize (with Foundry)')"
OUT="$(collect_out "$WORK/c")"; RC=$?
assert_contains "$OUT" "language: no decided SQ/CQ names the frontend language" \
  "multi-word parenthetical is not mistaken for a language"
assert_eq "1" "$RC" "…and the command stops rather than adopting it"
assert_contains "$OUT" "single-word" \
  "…and the message explains the single-word rule, so the fix is obvious"
# The stop message quotes the framework's own answer back, so the build tool's
# name DOES appear — as something the resolver read and declined to use. What
# must never happen is it being adopted, which is proved by the stop above and
# by nothing reaching the manifest.
assert_not_contains "$(collect_json "$WORK/c")" "Foundry" \
  "…and no collected output carries it as a resolved value"

# ── 4. Language decided separately, via the standard-bank SQ-015. ──────────
make_repo "$WORK/d" "$(fw_block 'Kestrelize')
$(lang_block 'Runescript')"
J="$(collect_json "$WORK/d")"
assert_eq "Kestrelize" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" "SQ-015 route: framework resolved"
assert_eq "Runescript" "$(printf '%s' "$J" | jq -r '.stack.language.value')" "SQ-015 route: language resolved"
assert_eq "SQ-015" "$(printf '%s' "$J" | jq -r '.stack.language.sanctioned_by')" "SQ-015 route: language cites SQ-015"
assert_eq "Priya Raman" "$(printf '%s' "$J" | jq -r '.stack.language.decided_by')" \
  "SQ-015 route: the language records its own decider, not the framework's"

# ── 5. Language raised as a CQ before SQ-015 existed — matched on the
# QUESTION'S ROLE, never on recognising the answer. ────────────────────────
make_repo "$WORK/e" "$(fw_block 'Kestrelize')
### CQ-031 — Frontend language for the rebuilt client

- **Family:** Extracted
- **Decision:** Runescript
- **Decided by:** Priya Raman
- **Date:** 2026-09-12
"
J="$(collect_json "$WORK/e")"
assert_eq "Runescript" "$(printf '%s' "$J" | jq -r '.stack.language.value')" "CQ route: language resolved"
assert_eq "CQ-031" "$(printf '%s' "$J" | jq -r '.stack.language.sanctioned_by')" "CQ route: language cites the CQ"

# ── 6. decisions.md is AUTHORITATIVE over a differing target-architecture.md
# row. The arch row is a summary /specclaw:bf-blueprint derives FROM the same
# decision, never a co-equal human source, so when decisions.md resolves SQ-006
# its value wins outright and the arch row is ignored — no "disagree" stop,
# whatever the arch row's wording. (A language is supplied so the run reaches a
# clean resolution rather than stopping on the missing language.) ────────────
make_repo "$WORK/f" "$(fw_block 'Kestrelize')
$(lang_block 'Runescript')" '| Legacy shell | Tessera | SQ-006 | DECIDED |'
J="$(collect_json "$WORK/f")"; RC=$?
assert_eq "0" "$RC" "decisions.md decides framework, arch row differs: collect succeeds"
assert_eq "Kestrelize" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" \
  "…and decisions.md's value wins outright"
assert_eq ".specclaw/analysis/decisions.md" "$(printf '%s' "$J" | jq -r '.stack.framework.source')" \
  "…and the source recorded is decisions.md, not the architecture doc"
assert_not_contains "$J" "Tessera" \
  "…and the differing derived arch value is never adopted"

# ── 7. Framework from target-architecture alone, when decisions.md is silent
# on SQ-006 but a DECIDED row cites it. ───────────────────────────────────
make_repo "$WORK/g" "$(lang_block 'Runescript')" '| Legacy shell | Tessera | SQ-006 | DECIDED |'
J="$(collect_json "$WORK/g")"
assert_eq "Tessera" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" \
  "architecture route: framework read from the DECIDED row citing SQ-006"
assert_eq ".specclaw/analysis/target-architecture.md" "$(printf '%s' "$J" | jq -r '.stack.framework.source')" \
  "architecture route: the source is recorded as the architecture document"

# ── 8. A row that is NOT decided decides nothing. ──────────────────────────
make_repo "$WORK/h" "$(lang_block 'Runescript')" '| Legacy shell | Tessera | SQ-006 | PROVISIONAL(CQ-009) |'
OUT="$(collect_out "$WORK/h")"
assert_contains "$OUT" "framework: SQ-006 undecided" \
  "a PROVISIONAL architecture row is not a decision"
assert_not_contains "$OUT" "Tessera" "…and its speculative target element is never adopted"

# ── 9. Nothing decided at all: the framework is named first, because it is
# the first thing missing. ────────────────────────────────────────────────
make_repo "$WORK/i" ""
OUT="$(collect_out "$WORK/i")"
assert_contains "$OUT" "framework: SQ-006 undecided" "nothing decided: stops on the framework"

# ── 10. THE STACK-BLINDNESS PROOF. Two invented stacks that no built-in list
# could contain. If either resolves, the resolver is recognising values
# instead of reading records — which is exactly how a real project's language
# would get defaulted from its framework's convention. ───────────────────
make_repo "$WORK/j" "$(fw_block 'Zibbleframe 9')
$(lang_block 'Quux++')"
J="$(collect_json "$WORK/j")"
assert_eq "Zibbleframe 9" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" \
  "stack-blind: an invented framework resolves exactly as a real one does"
assert_eq "Quux++" "$(printf '%s' "$J" | jq -r '.stack.language.value')" \
  "stack-blind: an invented language resolves exactly as a real one does"

# ── 11. And the converse: a framework whose real-world convention implies a
# language must STILL stop, because a convention is not a decision. ───────
make_repo "$WORK/k" "$(fw_block 'Next.js')"
OUT="$(collect_out "$WORK/k")"
assert_contains "$OUT" "language: no decided SQ/CQ names the frontend language" \
  "a framework with a well-known default language still stops on the language"

# ── 12. No value is ever synthesised: every resolved value appears verbatim
# in the record it was read from. ────────────────────────────────────────
make_repo "$WORK/l" "$(fw_block 'Kestrelize')
$(lang_block 'Runescript')"
J="$(collect_json "$WORK/l")"
FWV="$(printf '%s' "$J" | jq -r '.stack.framework.value')"
LANGV="$(printf '%s' "$J" | jq -r '.stack.language.value')"
if grep -qF "$FWV" "$WORK/l/.specclaw/analysis/decisions.md" \
   && grep -qF "$LANGV" "$WORK/l/.specclaw/analysis/decisions.md"; then
  ok "every resolved value appears verbatim in the decision record"
else
  bad "every resolved value appears verbatim in the decision record" "a value was synthesised"
fi

# ── 13. PD-02: a non-REINTERPRET repo never reaches the resolver at all. ──
make_repo "$WORK/m" "$(fw_block 'Kestrelize')"
sed -i 's/^- \*\*Decision:\*\* REINTERPRET.*$/- **Decision:** FAITHFUL — reproduce the legacy layout exactly./' \
  "$WORK/m/.specclaw/analysis/decisions.md"
OUT="$(collect_out "$WORK/m")"
assert_contains "$OUT" "not REINTERPRET" "FAITHFUL repo: stops on the policy, before the stack"
assert_not_contains "$OUT" "SQ-006 undecided" "…and never mentions a stack question it did not need"

echo
echo "== PD-03a regression — derived summaries are not rival authorities =="

# ── 14. THE REGRESSION THIS FIX EXISTS FOR (scenario 1): decisions.md holds
# SQ-006 as full human prose while target-architecture.md carries a SHORTER
# derived summary of the same choice, citing SQ-006. Before the fix these
# normalised-unequal strings raised a false "disagree" stop; now decisions.md
# is authoritative, its full text is the framework value, and the run proceeds.
make_repo "$WORK/n" "$(fw_block 'Kestrelize web client with the Foundry component kit as the primary library; exact packaging fixed in an implementation ADR.')
$(lang_block 'Runescript')" '| Legacy client | Kestrelize web client (Foundry) | SQ-006 | DECIDED |'
J="$(collect_json "$WORK/n")"; RC=$?
assert_eq "0" "$RC" "full-prose decision + shorter arch summary: collect succeeds (no false disagreement)"
assert_contains "$(printf '%s' "$J" | jq -r '.stack.framework.value')" "Kestrelize web client with the Foundry component kit" \
  "…and the framework value is decisions.md's full text, verbatim"
assert_eq ".specclaw/analysis/decisions.md" "$(printf '%s' "$J" | jq -r '.stack.framework.source')" \
  "…and decisions.md is the recorded source"

# ── 15. (scenario 2) A component library in the framework text's parenthetical
# — "(MUI)" — must never be read as the frontend language. SQ-015 decides the
# language and is authoritative; the parenthetical is not even consulted. Uses
# the real names from the bug that motivated this fix. ──────────────────────
make_repo "$WORK/o" "$(fw_block 'Next.js + TypeScript with Material UI (MUI) as the primary component library')
$(lang_block 'TypeScript')"
J="$(collect_json "$WORK/o")"; RC=$?
assert_eq "0" "$RC" "framework text contains (MUI), language decided by SQ-015: collect succeeds"
assert_eq "TypeScript" "$(printf '%s' "$J" | jq -r '.stack.language.value')" \
  "…and the language is TypeScript from SQ-015"
assert_eq "SQ-015" "$(printf '%s' "$J" | jq -r '.stack.language.sanctioned_by')" \
  "…and it cites SQ-015, not the framework's parenthetical"
assert_not_contains "$(printf '%s' "$J" | jq -r '.stack.language.value')" "MUI" \
  "…and the component library (MUI) is never mistaken for the language"

# ── 16. (scenario 3) Byte-identical framework wording in both records still
# resolves cleanly — the fix did not turn genuine agreement into a problem. ──
make_repo "$WORK/p" "$(fw_block 'Kestrelize')
$(lang_block 'Runescript')" '| Legacy shell | Kestrelize | SQ-006 | DECIDED |'
J="$(collect_json "$WORK/p")"; RC=$?
assert_eq "0" "$RC" "identical framework wording in both records: collect succeeds"
assert_eq "Kestrelize" "$(printf '%s' "$J" | jq -r '.stack.framework.value')" \
  "…and the framework resolves to that value"

echo
echo "prototype stack-resolver suite: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
