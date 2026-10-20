#!/usr/bin/env bash
# run-preset-check-tests.sh — change 042, Stage 3: one case per acceptance criterion (AC-10, AC-11).
# shellcheck disable=SC2016,SC2329  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$PLUGIN_DIR/bin"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# AC-10: six presets, each ≤60 lines; init proposes nextjs for a Next.js package.json.
bad=""
for p in base python nextjs node dotnet react-spa; do
  f="$PLUGIN_DIR/presets/$p.md"
  [ -f "$f" ] && [ "$(wc -l < "$f")" -le 60 ] || bad="$bad $p"
done
mkdir -p "$TMP/n" && printf '{"dependencies":{"next":"15.0.0"}}\n' > "$TMP/n/package.json"
"$BIN/specclaw-init" "$TMP/n" demo d >/dev/null
check "AC-10 presets exist ≤60 lines and init proposes nextjs:${bad:- ok}" '[ -z "$bad" ] && grep -q "^presets: \[nextjs\]" "$TMP/n/.specclaw/config.yaml"'

# AC-11: exit 1 on an 81-line file, a comment line and Domain→Infrastructure; 0 when clean.
fixture() { rm -rf "$TMP/c" && mkdir -p "$TMP/c/src" && printf 'export const ok = 1\n' > "$TMP/c/src/ok.ts"; }
rc() { "$BIN/specclaw-preset-check" "$TMP/c" >/dev/null 2>&1; echo $?; }
fixture
check "AC-11 clean tree exits 0" '[ "$(rc)" = 0 ]'
seq 81 | sed 's/^/x = /' > "$TMP/c/src/long.py"
check "AC-11 81-line file exits 1" '[ "$(rc)" = 1 ]'
fixture; printf '// explains the next line\nexport const b = 2\n' > "$TMP/c/src/b.ts"
check "AC-11 comment line exits 1" '[ "$(rc)" = 1 ]'
fixture; printf '<Project><ItemGroup><ProjectReference Include="../App.Infrastructure/App.Infrastructure.csproj" /></ItemGroup></Project>\n' > "$TMP/c/src/App.Domain.csproj"
check "AC-11 Domain→Infrastructure reference exits 1" '[ "$(rc)" = 1 ]'

# Change 045: specclaw-presets resolves project-local presets over built-ins.
P="$(cd "$PLUGIN_DIR/presets" && pwd -P)"
proj() { rm -rf "$TMP/p" && mkdir -p "$TMP/p/presets" && printf 'presets: [%s]\n' "$1" > "$TMP/p/config.yaml"; L="$(cd "$TMP/p/presets" && pwd -P)"; }
res() { "$BIN/specclaw-presets" "$TMP/p" 2>/dev/null | tr '\n' ' '; }
proj dotnet; rmdir "$TMP/p/presets"
check "AC-1 no local dir prints built-in base then dotnet" '[ "$(res)" = "$P/base.md $P/dotnet.md " ]'
proj dotnet; printf '# Preset: dotnet (ours)\n' > "$L/dotnet.md"
check "AC-2 local dotnet replaces built-in" '[ "$(res)" = "$P/base.md $L/dotnet.md " ]'
printf -- '---\nextends: dotnet\n---\n# more rules\n' > "$L/dotnet.md"
check "AC-3 frontmatter extends: dotnet prints built-in then local" '[ "$(res)" = "$P/base.md $P/dotnet.md $L/dotnet.md " ]'
proj "acme, nope"; printf '# acme\n' > "$L/acme.md"
"$BIN/specclaw-presets" "$TMP/p" >"$TMP/o" 2>"$TMP/e"; r=$?
check "AC-4 local acme printed, unknown nope warns and exits 1" '[ $r = 1 ] && [ "$(tr "\n" " " < "$TMP/o")" = "$P/base.md $L/acme.md " ] && grep -q "unknown preset .nope." "$TMP/e"'
proj "../x"
check "AC-5 path-like name is unknown" '! "$BIN/specclaw-presets" "$TMP/p" >/dev/null 2>&1'

# Variants of the presets: forms, extends frontmatter and the trust boundary. Each row:
# label | config.yaml body | local files (name=body;...) | expected rc | expected names (in order)
cfgcase() {
  local label="$1" cfg="$2" files="$3" want_rc="$4" want="$5" stray="${6:-}" got r f w
  rm -rf "$TMP/v" && mkdir -p "$TMP/v/presets"
  [ "$cfg" = "-" ] || printf '%b' "$cfg" > "$TMP/v/config.yaml"
  IFS=';' read -ra fs <<<"$files"
  for f in "${fs[@]}"; do [ -n "$f" ] && printf '%b' "${f#*=}" > "$TMP/v/presets/${f%%=*}.md"; done
  got="$("$BIN/specclaw-presets" "$TMP/v" 2>/dev/null | sed -E 's|.*/([^/]+)/presets/([^/]+)\.md$|\1:\2|' | tr '\n' ' ')"
  w="$("$BIN/specclaw-presets" "$TMP/v" 2>&1 >/dev/null)"; r=$?
  case "$stray" in
    warn)  grep -q "outside frontmatter has no effect" <<<"$w" || r=stray-missing ;;
    quiet) ! grep -q "outside frontmatter" <<<"$w" || r=stray-unexpected ;;
  esac
  check "045 variant: $label" '[ "$r" = "$want_rc" ] && [ "$got" = "$want" ]'
}
cfgcase "block list"                 'presets:\n  - dotnet\n  - python\n' ''                         0 "specclaw:base specclaw:dotnet specclaw:python "
cfgcase "trailing comment on key"    'presets:  # ours\n  - dotnet\n'      ''                         0 "specclaw:base specclaw:dotnet "
cfgcase "comment between items"      'presets:\n  # web\n  - nextjs\n'     ''                         0 "specclaw:base specclaw:nextjs "
cfgcase "column-0 dashes"            'presets:\n- node\nother: 1\n'        ''                         0 "specclaw:base specclaw:node "
cfgcase "CRLF flow form"             'presets: [python]\r\n'               ''                         0 "specclaw:base specclaw:python "
cfgcase "flow form with comment"     'presets: [node] # x\n'               ''                         0 "specclaw:base specclaw:node "
cfgcase "empty flow"                 'presets: []\n'                       ''                         0 "specclaw:base "
cfgcase "scalar is malformed"        'presets: python\n'                   ''                         1 "specclaw:base "
cfgcase "missing config"             '-'                                   ''                         1 "specclaw:base "
cfgcase "local base replaces"        'presets: []\n'                       'base=# ours\n'            0 "v:base "
cfgcase "fm: extends own built-in"   'presets: [dotnet]\n'                 'dotnet=---\nextends: dotnet\n---\n# ours\n' 0 "specclaw:base specclaw:dotnet v:dotnet " quiet
cfgcase "fm: extends another local"  'presets: [b]\n'                      'a=# a\n;b=---\nextends: a\n---\n' 0 "specclaw:base v:a v:b " quiet
cfgcase "fm: extends base keeps it"  'presets: []\n'                       'base=---\nextends: base\n---\n' 0 "specclaw:base v:base " quiet
cfgcase "fm: quoted value"           'presets: [a]\n'                      'a=---\nextends: "node"\n---\n' 0 "specclaw:base specclaw:node v:a " quiet
cfgcase "fm: unknown parent"         'presets: [a]\n'                      'a=---\nextends: zzz\n---\n' 1 "specclaw:base v:a "
cfgcase "fm: other key is an error"  'presets: [a]\n'                      'a=---\nextends: node\ntitle: x\n---\n' 1 "specclaw:base v:a "
cfgcase "fm: unclosed is an error"   'presets: [a]\n'                      'a=---\nextends: node\n# rules\n' 1 "specclaw:base v:a "
cfgcase "fm: not on line 1 only warns" 'presets: [a]\n'                   'a=# Ours\n---\nextends: node\n---\n' 0 "specclaw:base v:a " warn
cfgcase "old Extends: line only warns" 'presets: [a]\n'                   'a=# Ours\nExtends: node\n' 0 "specclaw:base v:a " warn
cfgcase "stray: ~~~ fence warns"       'presets: [a]\n'                     'a=~~~\nextends: node\n~~~\n' 0 "specclaw:base v:a " warn
cfgcase "stray: space before colon"  'presets: [a]\n'                     'a=Extends : node\n'        0 "specclaw:base v:a " warn
cfgcase "stray: indented line warns too (any line, by design)" 'presets: [a]\n'                     'a=    extends: node\n'    0 "specclaw:base v:a " warn
cfgcase "stray: after unclosed fence" 'presets: [a]\n'                    'a=```\nsample\nextends: node\n' 0 "specclaw:base v:a " warn
cfgcase "stray: heading word quiet"  'presets: [a]\n'                     'a=# Extends and overrides\n' 0 "specclaw:base v:a " quiet
cfgcase "stray: prose word quiet"    'presets: [a]\n'                     'a=Extends the base rules.\n' 0 "specclaw:base v:a " quiet
cfgcase "extends: in a fence warns" 'presets: [a]\n'                    'a=# Ours\n```\nextends: node\n```\n' 0 "specclaw:base v:a " warn
cfgcase "extends: after fm only warns" 'presets: [a]\n'                   'a=---\n---\nextends: node\n' 0 "specclaw:base v:a " warn
cfgcase "fm: BOM before ---"         'presets: [a]\n'                      'a=\xef\xbb\xbf---\nextends: node\n---\n' 0 "specclaw:base specclaw:node v:a " quiet
cfgcase "fm: CRLF"                   'presets: [a]\n'                      'a=---\r\nextends: node\r\n---\r\n' 0 "specclaw:base specclaw:node v:a " quiet
cfgcase "fm: empty"                  'presets: [a]\n'                      'a=---\n---\n# ours\n' 0 "specclaw:base v:a " quiet
cfgcase "fm: comment line"           'presets: [a]\n'                      'a=---\n# why\nextends: node\n---\n' 0 "specclaw:base specclaw:node v:a " quiet
cfgcase "fm: two extends"            'presets: [a]\n'                      'a=---\nextends: node\nextends: python\n---\n' 1 "specclaw:base v:a "
cfgcase "fm: capitalised key"        'presets: [a]\n'                      'a=---\nExtends: node\n---\n' 1 "specclaw:base v:a "
cfgcase "fm: mismatched quotes"      'presets: [a]\n'                      'a=---\nextends: "node\x27\n---\n' 1 "specclaw:base v:a "
cfgcase "block: ends at next key"    'presets:\n  - node\nbuild:\n  x: 1\n' ''                        0 "specclaw:base specclaw:node "
cfgcase "block: tab after dash"      'presets:\n  -\tnode\n'               ''                         1 "specclaw:base "
cfgcase "config: BOM before presets:" '\xef\xbb\xbfpresets: [node]\n' ''                      0 "specclaw:base specclaw:node "
cfgcase "fm: trailing comment"       'presets: [a]\n'                      'a=---\nextends: node  # keep it\n---\n' 0 "specclaw:base specclaw:node v:a " quiet
cfgcase "fm: child of a self-extending local" 'presets: [acme]\n'           'dotnet=---\nextends: dotnet\n---\n;acme=---\nextends: dotnet\n---\n' 0 "specclaw:base specclaw:dotnet v:dotnet v:acme " quiet
cfgcase "fm: same, parent listed first" 'presets: [dotnet, acme]\n'          'dotnet=---\nextends: dotnet\n---\n;acme=---\nextends: dotnet\n---\n' 0 "specclaw:base specclaw:dotnet v:dotnet v:acme " quiet
cfgcase "fm: same, child listed first" 'presets: [acme, dotnet]\n'           'dotnet=---\nextends: dotnet\n---\n;acme=---\nextends: dotnet\n---\n' 0 "specclaw:base specclaw:dotnet v:dotnet v:acme " quiet
cfgcase "fm: nested extends refused" 'presets: [a]\n'                      'a=---\nextends: b\n---\n;b=---\nextends: node\n---\n' 1 "specclaw:base v:b v:a "
cfgcase "fm: mutual cycle refused"   'presets: [a]\n'                      'a=---\nextends: b\n---\n;b=---\nextends: a\n---\n' 1 "specclaw:base v:b v:a "
cfgcase "fm: malformed parent"       'presets: [a]\n'                      'a=---\nextends: b\n---\n;b=---\nextends: node\n' 1 "specclaw:base v:b v:a "
cfgcase "dedupe repeated names"      'presets: [python, python, base]\n'  ''                         0 "specclaw:base specclaw:python "
cfgcase "block: indented scalar"     'presets:\n  - node\n  python\n'    ''                         1 "specclaw:base specclaw:node "
cfgcase "block: bare dash"           'presets:\n  -\n  - node\n'         ''                         1 "specclaw:base specclaw:node "
cfgcase "block: dash without space"  'presets:\n  -python\n'              ''                         1 "specclaw:base "
cfgcase "path-like names"            'presets: [../x, ../../etc/hosts]\n' ''                         1 "specclaw:base "
rm -rf "$TMP/v" && mkdir -p "$TMP/v/presets" && printf 'presets: [dotnet]\n' > "$TMP/v/config.yaml"
printf 'secret\n' > "$TMP/outside.md" && ln -s "$TMP/outside.md" "$TMP/v/presets/dotnet.md"
sym1="$("$BIN/specclaw-presets" "$TMP/v" 2>/dev/null | sed -E 's|.*/([^/]+)/presets/([^/]+)\.md$|\1:\2|' | tr '\n' ' ')"
check "045 variant: refused local file does not fall back to the built-in" '[ "$sym1" = "specclaw:base " ]'
check "045 variant: symlink out of presets/ is refused" '! "$BIN/specclaw-presets" "$TMP/v" 2>/dev/null | grep -q outside.md && ! "$BIN/specclaw-presets" "$TMP/v" >/dev/null 2>&1'
rm "$TMP/v/presets/dotnet.md" && printf 'presets: [a]\n' > "$TMP/v/config.yaml" && printf -- '---\nextends: b\n---\n' > "$TMP/v/presets/a.md"
ln -s "$TMP/outside.md" "$TMP/v/presets/b.md"
sym="$("$BIN/specclaw-presets" "$TMP/v" 2>/dev/null | sed -E 's|.*/([^/]+)/presets/([^/]+)\.md$|\1:\2|' | tr '\n' ' ')"
check "045 variant: symlinked extends parent is refused" '[ "$sym" = "specclaw:base v:a " ] && ! "$BIN/specclaw-presets" "$TMP/v" >/dev/null 2>&1'
for kind in dangling directory; do
  rm -rf "$TMP/v" && mkdir -p "$TMP/v/presets" && printf 'presets: [dotnet]\n' > "$TMP/v/config.yaml"
  if [ "$kind" = dangling ]; then ln -s "$TMP/no-such.md" "$TMP/v/presets/dotnet.md"; else mkdir "$TMP/v/presets/dotnet.md"; fi
  out1="$("$BIN/specclaw-presets" "$TMP/v" 2>/dev/null | sed -E 's|.*/([^/]+)/presets/([^/]+)\.md$|\1:\2|' | tr '\n' ' ')"
  check "045 variant: $kind dotnet.md is refused, no built-in fallback" '[ "$out1" = "specclaw:base " ] && ! "$BIN/specclaw-presets" "$TMP/v" >/dev/null 2>&1'
done
mkdir -p "$TMP/i" && "$BIN/specclaw-init" "$TMP/i" demo d >/dev/null
check "AC-6 init scaffolds .specclaw/presets/README.md from the template" 'cmp -s "$TMP/i/.specclaw/presets/README.md" "$PLUGIN_DIR/templates/presets-README.md"'
check "AC-7 lean build reads presets via specclaw-presets" 'grep -q "specclaw-presets .specclaw" "$PLUGIN_DIR/skills/build/SKILL.md" && ! grep -q "presets/base.md" "$PLUGIN_DIR/skills/build/SKILL.md"'

echo
[ "$FAILS" -eq 0 ] && echo "All preset-check tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
