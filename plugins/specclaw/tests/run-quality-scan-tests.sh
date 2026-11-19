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

# Change 068 AC-1: each table larger than the OS argument limit must reach jq by file.
# BIG names the table the fakes inflate: funcs (lizard rows), dup (jscpd summary rows), clones (jscpd pairs).
mkdir -p "$TMP/fakebig" "$TMP/pbig/src"
for f in jq git mktemp; do cp -P "$FAKE/$f" "$TMP/fakebig/$f"; done; ln -s "$BASH" "$TMP/fakebig/bash"
cat > "$TMP/fakebig/lizard" <<'LZ'
#!/usr/bin/env bash
echo 'NLOC,CCN,token,PARAM,length,location,file,function,long_name,start,end'
n=1; [ "${BIG:-}" = funcs ] && n=25000
awk -v n="$n" 'BEGIN { for (i = 1; i <= n; i++) printf "3,1,9,0,3,\"fn_%d@%d-%d@./src/a.ts\",\"./src/a.ts\",\"function_with_a_long_name_%d\",\"function_with_a_long_name_%d( )\",%d,%d\n", i, i, i, i, i, i, i }'
LZ
cat > "$TMP/fakebig/jscpd" <<'JS'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
mkdir -p "$out"
ls src | LC_ALL=C sort | jq -R -s --arg big "${BIG:-}" 'split("\n") | map(select(length > 0) | "src/" + .) as $f
  | {duplicates: (if $big == "clones" then [range(8000) | {lines: 2, fragment: "x", firstFile: {name: $f[0], start: 1, end: 2}, secondFile: {name: $f[1], start: 1, end: 2}}] else [] end),
     summary: {by: "lines", files: ((if $big == "dup" then $f else $f[0:2] end) | map({path: ., lines: 1}))}}' > "$out/jscpd-report.json"
JS
chmod +x "$TMP/fakebig/lizard" "$TMP/fakebig/jscpd"
long="$(printf 'x%.0s' {1..190})"
(cd "$TMP/pbig" && git init -q && printf 'export const a = 1\n' > src/a.ts && for i in $(seq 1 12000); do : > "src/f${i}_$long.ts"; done)
for row in "funcs .totals.functions 25000" "dup .totals.lines 12001" "clones .duplicates|length 8000"; do
  read -r tab path want <<<"$row"
  size="$(cd "$TMP/pbig" && BIG="$tab" PATH="$TMP/fakebig:/usr/bin:/bin" bash -c 'lizard; jscpd --output "$0" >/dev/null; cat "$0/jscpd-report.json"' "$TMP/sz-$tab" | wc -c)"
  out="$(cd "$TMP/pbig" && BIG="$tab" PATH="$TMP/fakebig:/usr/bin:/bin" "$SCAN" . --gate)"; rc=$?
  check "068 AC-1 oversized $tab table (${size} bytes > ARG_MAX) → report written, gate exit, not 126" \
    '[ "$size" -gt "$(getconf ARG_MAX)" ] && [ "$rc" != 126 ] && [ "$rc" -le 2 ] && [ "$(jq -r "$path" <<<"$out")" = "$want" ]'
done

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
