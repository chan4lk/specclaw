#!/usr/bin/env bash
# run-build-context-security-tests.sh — change 072 AC-1: builder payloads carry the
# `## Security` sections of the resolved presets (base + stacks, overrides win).
# shellcheck disable=SC2016  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONTEXT="$PLUGIN_DIR/bin/specclaw-build-context"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# project <dir> — a minimal .specclaw project with presets: [node] and one task.
project() {
  mkdir -p "$1/.specclaw/changes/demo"
  printf 'project:\n  name: demo\ngit:\n  commit_prefix: specclaw\npresets: [node]\n' > "$1/.specclaw/config.yaml"
  printf '# Tasks\n\n- [ ] `T1` — do it\n  - Files: a.txt\n' > "$1/.specclaw/changes/demo/tasks.md"
  printf '# Spec\n' > "$1/.specclaw/changes/demo/spec.md"
}
payload() { ( cd "$1" && "$BUILD_CONTEXT" .specclaw demo T1 2>/dev/null ); }

# 1: built-in base + node security rules are injected.
project "$TMP/a"
P="$(payload "$TMP/a")"
check "AC-1 section present" 'printf "%s" "$P" | grep -q "^## Stack Security Rules$"'
check "AC-1 base rules under ### base" 'printf "%s" "$P" | grep -q "^### base$" && printf "%s" "$P" | grep -qF "**DevFlags:**"'
check "AC-1 node rules under ### node" 'printf "%s" "$P" | grep -q "^### node$" && printf "%s" "$P" | grep -qF "**Proxy:**"'
check "AC-1 non-security preset sections stay out" '! printf "%s" "$P" | grep -q "^## Duplication$"'

# 2: a project override of node replaces the built-in's rules.
project "$TMP/b"
mkdir -p "$TMP/b/.specclaw/presets"
printf '# node (project)\n\n## Security\n- OVERRIDE-MARKER-072\n\n## Rules\n- not security\n' > "$TMP/b/.specclaw/presets/node.md"
P="$(payload "$TMP/b")"
check "AC-1 override marker present" 'printf "%s" "$P" | grep -qF "OVERRIDE-MARKER-072"'
check "AC-1 built-in node rule absent" '! printf "%s" "$P" | grep -qF "**Proxy:**"'
check "AC-1 override non-security section absent" '! printf "%s" "$P" | grep -qF "not security"'

# 3: no resolved preset has a ## Security section → no heading at all.
project "$TMP/c"
mkdir -p "$TMP/c/.specclaw/presets"
printf '# base (project)\n\n## Code\n- small\n' > "$TMP/c/.specclaw/presets/base.md"
printf '# node (project)\n\n## Rules\n- tidy\n' > "$TMP/c/.specclaw/presets/node.md"
P="$(payload "$TMP/c")"
check "AC-1 payload still built" 'printf "%s" "$P" | grep -q "^## Specification Context$"'
check "AC-1 no section without ## Security" '! printf "%s" "$P" | grep -q "Stack Security Rules"'

if [ "$FAILS" -eq 0 ]; then echo "All build-context security tests passed."; else echo "$FAILS build-context security test(s) failed."; fi
[ "$FAILS" -eq 0 ]
