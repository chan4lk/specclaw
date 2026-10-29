#!/usr/bin/env bash
# run-quality-scan-tests.sh — change 042, Stage 4: one case per acceptance criterion (AC-12).
# jscpd and lizard are faked on PATH so the suite needs no network; the fakes emit
# the real tools' report shapes (jscpd v5 JSON, lizard --csv).
# shellcheck disable=SC2016,SC2329  # check() evals its single-quoted condition later, by design
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$PLUGIN_DIR/bin/specclaw-quality-scan"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fake"; mkdir -p "$FAKE" "$TMP/p/src"
for t in jq git mktemp; do ln -s "$(command -v "$t")" "$FAKE/$t"; done; ln -s "$BASH" "$FAKE/bash"
cat > "$FAKE/jscpd" <<'JS'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
mkdir -p "$out"
cat > "$out/jscpd-report.json" <<'J'
{"duplicates":[{"lines":20,"fragment":"x","firstFile":{"name":"src/a.ts","start":1,"end":20},"secondFile":{"name":"src/b.ts","start":3,"end":22}}],
 "summary":{"by":"lines","files":[{"path":"src/a.ts","lines":22},{"path":"src/b.ts","lines":22}]}}
J
JS
cat > "$FAKE/lizard" <<'LZ'
#!/usr/bin/env bash
echo 'NLOC,CCN,token,PARAM,length,location,file,function,long_name,start,end'
echo '20,2,90,1,20,"alpha@1-20@./src/a.ts","./src/a.ts","alpha","alpha( x )",1,20'
LZ
chmod +x "$FAKE/jscpd" "$FAKE/lizard"
(cd "$TMP/p" && git init -q && printf 'export const a = 1\n' > src/a.ts && cp src/a.ts src/b.ts)
run() { (cd "$TMP/p" && PATH="$1:/usr/bin:/bin" "$SCAN" . "${@:2}"); }

# AC-12: a planted 20-line duplicate is listed with both locations; --gate exits 1 above duplication_high.
out="$(run "$FAKE")"
check "AC-12 duplicate listed with both locations" '[ "$(jq -c ".duplicates[0] | [.lines, .a.file, .a.start, .b.file, .b.start]" <<<"$out")" = "[20,\"src/a.ts\",1,\"src/b.ts\",3]" ]'
run "$FAKE" --gate >/dev/null; rc=$?
check "AC-12 --gate exits 1 above the high threshold" '[ "$rc" = 1 ]'

# Change 046: zero clones must still measure every scanned file. An empty duplicated list used to
# defeat the NR == FNR join, leaving jscpd at parse_error and the gate at not_run.
mkdir -p "$TMP/fake0" "$TMP/p0/src"
for t in jq git mktemp; do ln -s "$(command -v "$t")" "$TMP/fake0/$t"; done; ln -s "$BASH" "$TMP/fake0/bash"
cp "$FAKE/lizard" "$TMP/fake0/lizard"
cat > "$TMP/fake0/jscpd" <<'JS'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
mkdir -p "$out"
cat > "$out/jscpd-report.json" <<'J'
{"duplicates":[],"summary":{"by":"lines","files":[{"path":"src/a.ts","lines":1},{"path":"src/b.ts","lines":1}]}}
J
JS
chmod +x "$TMP/fake0/jscpd" "$TMP/fake0/lizard"
(cd "$TMP/p0" && git init -q && printf 'export const a = 1\n' > src/a.ts && printf 'export const b = 2\n' > src/b.ts)
out="$(cd "$TMP/p0" && PATH="$TMP/fake0:/usr/bin:/bin" "$SCAN" . --gate)"; rc=$?
check "046 zero clones → jscpd ran, 0 duplicated lines, gate pass" '[ "$rc" = 0 ] && [ "$(jq -r .tools.jscpd <<<"$out")" = ran ] && [ "$(jq -r .totals.duplicated_lines <<<"$out")" = 0 ] && [ "$(jq -r .gate <<<"$out")" = pass ]'

# Zero clones: jscpd reports no duplicates, so the join's first file is empty. Every
# scanned file must still be measured at 0 duplicated lines and the gate must pass.
ZERO="$TMP/zero"; mkdir -p "$ZERO"
for t in jq git mktemp; do ln -s "$(command -v "$t")" "$ZERO/$t"; done; ln -s "$BASH" "$ZERO/bash"
cp "$FAKE/lizard" "$ZERO/lizard"
cat > "$ZERO/jscpd" <<'JS'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
mkdir -p "$out"
cat > "$out/jscpd-report.json" <<'J'
{"duplicates":[],
 "summary":{"by":"lines","files":[{"path":"src/a.ts","lines":22},{"path":"src/b.ts","lines":22}]}}
J
JS
chmod +x "$ZERO/jscpd"
out="$(run "$ZERO" --gate)"; rc=$?
check "zero clones: jscpd ran, 0 duplicated lines" '[ "$(jq -r .tools.jscpd <<<"$out")" != not_run ] && [ "$(jq -r ".duplicates | length" <<<"$out")" = 0 ]'
check "zero clones: --gate passes (exit 0)" '[ "$rc" = 0 ]'

# Edge case: tools absent → not_run (never zero duplicates), --gate exits 2.
# The bare PATH mirrors /usr/bin and /bin minus every way to reach the tools, so
# the case holds on a runner whose /usr/bin carries npx or uvx.
mkdir -p "$TMP/bare"
for f in /usr/bin/* /bin/* "$(command -v jq)" "$(command -v git)"; do
  case "${f##*/}" in npx|uvx|lizard|jscpd|bash) continue ;; esac
  [ -e "$TMP/bare/${f##*/}" ] || ln -s "$f" "$TMP/bare/${f##*/}"
done
ln -s "$BASH" "$TMP/bare/bash"
out="$(cd "$TMP/p" && PATH="$TMP/bare" "$SCAN" . --gate)"; rc=$?
check "edge: tools absent → not_run and --gate exits 2" '[ "$rc" = 2 ] && [ "$(jq -r .tools.jscpd <<<"$out")" = not_run ]'

echo
[ "$FAILS" -eq 0 ] && echo "All quality-scan tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
