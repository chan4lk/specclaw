#!/usr/bin/env bash
# run-codex-plugin-tests.sh — verify the native Codex marketplace package.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
MARKETPLACE_FILE="$REPO_ROOT/.agents/plugins/marketplace.json"
CODEX_MANIFEST="$PLUGIN_DIR/.codex-plugin/plugin.json"
CLAUDE_MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/ci.yml"

failed=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[ -f "$MARKETPLACE_FILE" ] \
  && pass "Codex marketplace manifest exists" \
  || fail "Codex marketplace manifest exists at .agents/plugins/marketplace.json"

[ -f "$CODEX_MANIFEST" ] \
  && pass "native Codex plugin manifest exists" \
  || fail "native Codex plugin manifest exists at plugins/specclaw/.codex-plugin/plugin.json"

if [ -f "$MARKETPLACE_FILE" ] && [ -f "$CODEX_MANIFEST" ]; then
  python3 - "$MARKETPLACE_FILE" "$CODEX_MANIFEST" "$CLAUDE_MANIFEST" "$PLUGIN_DIR" <<'PY' \
    && pass "marketplace and plugin manifests satisfy the package contract" \
    || fail "marketplace and plugin manifests satisfy the package contract"
import json
import os
import sys

marketplace_path, codex_path, claude_path, plugin_dir = sys.argv[1:]
with open(marketplace_path, encoding="utf-8") as handle:
    marketplace = json.load(handle)
with open(codex_path, encoding="utf-8") as handle:
    codex = json.load(handle)
with open(claude_path, encoding="utf-8") as handle:
    claude = json.load(handle)

assert marketplace["name"] == "chan4lk"
root = os.path.dirname(os.path.dirname(os.path.dirname(marketplace_path)))
names = [p["name"] for p in marketplace["plugins"]]
assert names == ["specclaw", "specclaw-bf", "specclaw-sync", "specclaw-extras", "specclaw-review", "specclaw-fleet"], names
versions = set()
for entry in marketplace["plugins"]:
    pdir = os.path.join(root, "plugins", entry["name"])
    assert entry["source"] == {"source": "local", "path": "./plugins/" + entry["name"]}
    with open(os.path.join(pdir, ".codex-plugin", "plugin.json"), encoding="utf-8") as h:
        cx = json.load(h)
    with open(os.path.join(pdir, ".claude-plugin", "plugin.json"), encoding="utf-8") as h:
        cl = json.load(h)
    assert cx["skills"] == "./skills/"
    for field in ("name", "version", "description", "author", "homepage", "repository", "license", "keywords"):
        assert cx[field] == cl[field], (entry["name"], field)
    versions.add(cx["version"])
with open(os.path.join(root, ".claude-plugin", "marketplace.json"), encoding="utf-8") as h:
    versions |= {p["version"] for p in json.load(h)["plugins"]}
assert len(versions) == 1, versions
PY
fi

if [ -f "$CODEX_MANIFEST" ]; then
  for skill_dir in "$PLUGIN_DIR"/../specclaw*/skills/*; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -f "$skill_dir/SKILL.md" ] \
      && pass "canonical skill is packaged: $skill_name" \
      || fail "canonical skill is packaged: $skill_name"
  done
fi

# Codex parses every plugin's hooks/hooks.json and refuses unknown keys (0.8.6 shipped `modules` there and lost the SessionStart router in Codex).
for hooks_file in "$REPO_ROOT"/plugins/*/hooks/hooks.json; do
  rel="${hooks_file#"$REPO_ROOT"/}"
  extra="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(sorted(set(d) - {"description", "hooks"})) if isinstance(d, dict) else "not-an-object")' "$hooks_file" 2>/dev/null)" \
    && [ -z "$extra" ] \
    && pass "$rel holds only keys Codex accepts" \
    || fail "$rel holds only keys Codex accepts (found: ${extra:-unparsable})"
done

python3 - "$CLAUDE_MANIFEST" "$PLUGIN_DIR/hooks/mod.json" <<'PY' \
  && pass "the Claude manifest loads the mod and the Claude-only Stop done guard from hooks/mod.json" \
  || fail "the Claude manifest loads the mod and the Claude-only Stop done guard from hooks/mod.json"
import json, sys
manifest, mod = (json.load(open(path)) for path in sys.argv[1:3])
assert manifest.get("hooks") == "./hooks/mod.json", manifest.get("hooks")
assert mod["modules"] == ["./register.tsx"], mod
assert mod["hooks"]["Stop"][0]["hooks"][0]["command"].endswith('/hooks/done-guard"'), mod
PY

[ -f "$WORKFLOW_FILE" ] || fail "CI workflow exists"
if [ -f "$WORKFLOW_FILE" ]; then
  grep -Fq 'run: bash plugins/specclaw/tests/run-codex-plugin-tests.sh' "$WORKFLOW_FILE" \
    && pass "CI runs the Codex package contract" \
    || fail "CI runs the Codex package contract"

  grep -Fq "plugins/specclaw/.codex-plugin/plugin.json" "$WORKFLOW_FILE" \
    && pass "CI parses the native Codex manifest" \
    || fail "CI parses the native Codex manifest"
fi

[ "$failed" -eq 0 ] || exit 1
printf 'All Codex plugin package checks passed.\n'
