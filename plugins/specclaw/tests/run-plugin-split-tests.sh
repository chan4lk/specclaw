#!/usr/bin/env bash
# run-plugin-split-tests.sh — change 042, Stage 2: one case per acceptance criterion (AC-6..AC-8).
# shellcheck disable=SC2016,SC2329  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$PLUGIN_DIR/../.." && pwd)"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# AC-6: core skills and references carry no brownfield text.
check "AC-6 core has no bf/brownfield/rebuild mentions" '! grep -rqiE "bf-|brownfield|rebuild" "$PLUGIN_DIR/skills" "$PLUGIN_DIR/references"'

# AC-7: every plugin, each with both manifests, one shared version everywhere. specclaw-dash is a mod
# only (change 062): mods do not run in Codex, so its Codex manifest is metadata only (no skills) and
# it is left out of .agents/plugins/marketplace.json. ci.yml requires the manifest for every plugin.
check "AC-7 every plugin has its manifests and one shared version" 'python3 - "$REPO" <<"PY"
import glob, json, sys
r = sys.argv[1]
names = [p["name"] for p in json.load(open(r + "/.claude-plugin/marketplace.json"))["plugins"]]
assert names == ["specclaw", "specclaw-bf", "specclaw-sync", "specclaw-extras", "specclaw-review", "specclaw-fleet", "specclaw-dash"], names
vs = {json.load(open(f))["version"] for n in names for f in glob.glob(f"{r}/plugins/{n}/.c*-plugin/plugin.json")}
vs |= {p["version"] for p in json.load(open(r + "/.claude-plugin/marketplace.json"))["plugins"]}
assert len(glob.glob(r + "/plugins/*/.claude-plugin/plugin.json")) == len(names) and len(vs) == 1, vs
assert sorted(glob.glob(r + "/plugins/*/.codex-plugin/plugin.json")) == sorted(f"{r}/plugins/{n}/.codex-plugin/plugin.json" for n in names)
dash = json.load(open(r + "/plugins/specclaw-dash/.codex-plugin/plugin.json"))
assert "skills" not in dash and "hooks" not in dash, dash
assert "specclaw-dash" not in [p["name"] for p in json.load(open(r + "/.agents/plugins/marketplace.json"))["plugins"]]
PY'

# AC-8: github.sync on, specclaw-sync absent → install notice, and the lean flow still validates.
"$PLUGIN_DIR/bin/specclaw-init" "$TMP/p" demo d >/dev/null
sed -i.bak '/^github:/,/^[a-z]/ s/^  sync: false/  sync: true/' "$TMP/p/.specclaw/config.yaml"
mkdir -p "$TMP/p/.specclaw/changes/001-x"
printf '# X\n\n## Tasks\n\n- [ ] `T1` — Mock (AC-1)\n  - Files: a\n\n## Verify\n' > "$TMP/p/.specclaw/changes/001-x/change.md"
mkdir -p "$TMP/cache/chan4lk/specclaw/0.8.0"
out="$(cd "$TMP/p" && PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$TMP/cache/chan4lk/specclaw/0.8.0" bash "$PLUGIN_DIR/hooks/session-start")"
mkdir -p "$TMP/cache/chan4lk/specclaw-sync/0.8.0/bin" && : > "$TMP/cache/chan4lk/specclaw-sync/0.8.0/bin/specclaw-gh-sync"
out2="$(cd "$TMP/p" && PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="$TMP/cache/chan4lk/specclaw/0.8.0" bash "$PLUGIN_DIR/hooks/session-start")"
check "AC-8 hook names the missing specclaw-sync plugin, and not an installed one" 'grep -q "install specclaw-sync@chan4lk" <<<"$out" && ! grep -q "install specclaw-sync@chan4lk" <<<"$out2"'
check "AC-8 lean change validates without specclaw-sync" '(cd "$TMP/p" && PATH="/usr/bin:/bin" "$PLUGIN_DIR/bin/specclaw-validate-change" .specclaw 001-x build >/dev/null)'

echo
[ "$FAILS" -eq 0 ] && echo "All plugin-split tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
