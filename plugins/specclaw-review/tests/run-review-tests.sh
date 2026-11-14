#!/usr/bin/env bash
# run-review-tests.sh — regression suite for specclaw-review (change 044-fast-review-loop).
#
# One case per acceptance criterion, AC-1..AC-17. Offline: the model backend is a
# stub (`review.backend: "cat <file>"`), so no network and no model call. jq-free.
# shellcheck disable=SC2016,SC2034,SC2329  # check() evals its single-quoted condition later, so the vars and helpers it reads look unused
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$PLUGIN_DIR/../.." && pwd)"
SR="$PLUGIN_DIR/bin/specclaw-review"
GUARD="$PLUGIN_DIR/hooks/guard-memory"
FAILS=0
ok() { echo "PASS: $1"; }
ko() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }

TMP="$(mktemp -d)"
if [ -n "${KEEP:-}" ]; then echo "TMP=$TMP"; else trap 'rm -rf "$TMP"' EXIT; fi
export PYTHONDONTWRITEBYTECODE=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# A repo on `main` with a change branch `feat` that edits helper_fn, which b.py calls.
# The change name carries regex/shell metacharacters on purpose.
CH='001-a.b[x]$'
mkrepo() {
  local d="$1"
  mkdir -p "$d/.specclaw/changes/$CH" && cd "$d" || exit 1
  git init -q -b main
  printf 'def helper_fn(a):\n    return a\n' > a.py
  printf 'from a import helper_fn\nhelper_fn(1)\n' > b.py
  printf 'presets: [python, nosuchpack]\ngit:\n  base_branch: main\nreview:\n  backend: "cat %s.out.json"\n  rule_overrides:\n    B9: minor\n  models:\n    round: small-m\n    final: big-m\n' "$d" > .specclaw/config.yaml
  echo '[]' > "$d.out.json"
  git add -A && git commit -qm init && git checkout -qb feat
  printf 'def helper_fn(a):\n    return a + 1\n' > a.py
  git commit -qam change
}
out_json() { printf '%s' "$1" > "$(git rev-parse --show-toplevel).out.json"; }
MAJOR='[{"severity":"major","rule":"B1","file":"a.py","line":2,"message":"off by one","scenario":"helper_fn(1) returns 2","in_delta":true}]'
MINOR='[{"severity":"minor","rule":"B10","file":"a.py","line":1,"message":"naming","in_delta":true}]'
field() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }
RD=".specclaw/changes/$CH/review"

mkrepo "$TMP/r"

# AC-1: rulebook order, presets fallback, unknown pack note, repo rules, overrides.
mkdir -p .specclaw/review/rules && printf '## Repo\n- **R1** repo law\n' > .specclaw/review/rules/a-law.md
book="$("$SR" rules 2>"$TMP/notes")"
check "AC-1 base, then preset pack, then repo rules, then overrides" 'python3 - "$book" <<"PY"
import sys; b = sys.argv[1]
i = [b.index(s) for s in ("## Base rules", "## Python rules", "**R1** repo law", "## Severity overrides")]
assert i == sorted(i), i
assert "B9: at most minor" in b
PY'
check "AC-1 unknown pack is a note, not a failure" 'grep -q "nosuchpack" "$TMP/notes"'

# AC-2: classify skip vs review; risky path selects the final model.
check "AC-2 a code change classifies as review" '[ "$("$SR" classify | head -1)" = review ]'
git checkout -q -b recs main && mkdir -p .specclaw/x && echo r > .specclaw/x/r.md && echo d > NOTES.md && git add -A && git commit -qm recs
check "AC-2 records/docs-only classifies as skip" '[ "$("$SR" classify | head -1)" = skip ]'
git checkout -q feat

# AC-3: a major with a scenario → exit 1 and round-1.json; minors only → exit 0.
out_json "$MAJOR"; "$SR" run --change "$CH" >/dev/null; rc=$?
check "AC-3 major with scenario exits 1 and writes round-1.json" '[ "$rc" = 1 ] && [ -f "$RD/round-1.json" ] && [ "$(field "$RD/round-1.json" "d[\"model\"]")" = small-m ]'
out_json "$MINOR"; "$SR" run --change "$CH" >/dev/null; rc=$?
check "AC-3 minors only exits 0 and lands in follow-ups.md" '[ "$rc" = 0 ] && grep -q "naming" ".specclaw/changes/$CH/follow-ups.md"'

# AC-4: backend failure and unparsable output fail closed.
mkrepo "$TMP/r4"
printf 'presets: []\ngit:\n  base_branch: main\nreview:\n  backend: "false"\n' > .specclaw/config.yaml
"$SR" run --change "$CH" >/dev/null 2>&1; rc=$?
check "AC-4 backend failure exits 3, status not_run" '[ "$rc" = 3 ] && [ "$(field "$RD/round-1.json" "d[\"status\"]")" = not_run ]'
printf 'presets: []\ngit:\n  base_branch: main\nreview:\n  backend: "echo looks fine to me"\n' > .specclaw/config.yaml
"$SR" run --change "$CH" >/dev/null 2>&1; rc=$?
check "AC-4 prose with no JSON array exits 3, verdict never clean" '[ "$rc" = 3 ] && ! "$SR" verdict --change "$CH" >/dev/null'

# AC-5: calibration in code.
cd "$TMP/r" || exit 1
out_json '[{"severity":"major","rule":"B1","file":"a.py","line":2,"message":"no scenario"},
 {"severity":"major","rule":"B1","file":"README.md","line":1,"message":"doc","scenario":"x"},
 {"severity":"minor","rule":"B4","file":"a.py","line":5,"message":"dup one"},
 {"severity":"major","rule":"B4","file":"a.py","line":6,"message":"dup two","scenario":"x"},
 {"severity":"major","rule":"B6","file":"b.py","line":1,"message":"old","scenario":"x","in_delta":false}]'
"$SR" run --change "$CH" >/dev/null; rc=$?
last="$RD/round-$(find "$RD" -name "round-*.json" | wc -l | tr -d " ").json"
check "AC-5 scenario-less major and doc-file major become minor; dups collapse; pre-existing not counted" 'python3 - "$last" "$rc" <<"PY"
import json, sys
d = json.load(open(sys.argv[1])); f = {x["message"]: x for x in d["findings"]}
assert f["no scenario"]["severity"] == "minor" and f["doc"]["severity"] == "minor"
assert "dup one" not in f and f["dup two"]["severity"] == "major"
assert f["old"]["pre_existing"] is True
assert d["counts"]["major"] == 1 and sys.argv[2] == "1", (d["counts"], sys.argv[2])
PY'

# AC-6: --since excludes code merged from the base branch.
git checkout -q main && printf 'def base_only():\n    return 1\n' > c.py && git add c.py && git commit -qm base && git checkout -q feat
since="$(git rev-parse HEAD)"
git merge -q --no-edit main && printf 'def helper_fn(a):\n    return a + 2\n' > a.py && git commit -qam fix
cls="$("$SR" classify --since "$since")"
check "AC-6 --since lists the PR's own fix, not the merged base file" 'grep -q "a.py" <<<"$cls" && ! grep -q "c.py" <<<"$cls"'

# AC-7: impact set names the caller of the changed function.
out_json '[]'; "$SR" run --change "$CH" --since "$since" >/dev/null
last="$RD/round-$(find "$RD" -name "round-*.json" | wc -l | tr -d " ").json"
check "AC-7 impact set lists b.py (calls helper_fn)" 'grep -q "b.py" <<<"$(field "$last" "d[\"impact\"]")"'

# AC-8: same rule+file open in two earlier rounds → exit 4.
mkrepo "$TMP/r8"
out_json "$MAJOR"; "$SR" run --change "$CH" >/dev/null; "$SR" run --change "$CH" >/dev/null; "$SR" run --change "$CH" >/dev/null; rc=$?
v="$("$SR" verdict --change "$CH")"
check "AC-8 third round with the same finding escalates (exit 4)" '[ "$rc" = 4 ] && grep -q ESCALATE <<<"$v"'

# AC-9: verdict only with a clean final pass at HEAD; records-only commits keep it; code invalidates it.
mkrepo "$TMP/r9"
out_json '[]'; "$SR" run --change "$CH" >/dev/null
check "AC-9 clean round without a final pass is not OK" '! "$SR" verdict --change "$CH" >/dev/null'
"$SR" run --change "$CH" --final >/dev/null
check "AC-9 clean final pass at HEAD is OK and used the final model" '"$SR" verdict --change "$CH" >/dev/null && [ "$(field "$RD/round-2.json" "d[\"model\"]")" = big-m ]'
git add -A && git commit -qm records
check "AC-9 records-only commit after the final pass keeps it OK" '"$SR" verdict --change "$CH" >/dev/null'
echo 'x = 1' >> b.py && git commit -qam code
check "AC-9 code commit after the final pass makes it not OK" '! "$SR" verdict --change "$CH" >/dev/null'

# AC-10: memory dedupe, budget bound at 5000 entries, compact cap.
check "AC-10 memory dedupe, budget and compaction" 'python3 - "$PLUGIN_DIR/lib" "$TMP/mem" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_memory as m
d = sys.argv[2]
m.put(d, [{"rule": "B1", "file": "a.py", "message": "same lesson here", "severity": "major"}])
r = m.put(d, [{"rule": "B1", "file": "a.py", "message": "same lesson here", "severity": "major"}])
assert r == {"added": 0, "bumped": 1, "total": 1}, r
m.put(d, [{"rule": "B%d" % i, "file": "src/f%d.py" % i, "message": "lesson %d " % i + "x" * 200, "severity": "major"} for i in range(5000)])
q = m.query(d, ["src/f1.py"], budget=300, k=50)
assert 0 < (len(q) + 3) // 4 <= 300, len(q)
m.mark(d, {e["fp"] for e in m.load(d)[:10]}, "retired")
r = m.compact(d, d, max_entries=100)
assert r["after"] == 100 and not any(e["status"] == "retired" for e in m.load(d))
PY'

# AC-11: guard hook deny matrix.
deny() { printf '%s' "$1" | python3 "$GUARD" | grep -q '"deny"'; }
MP=/p/.specclaw/review-memory/findings.jsonl
all_denied=1
for t in Read Edit Write MultiEdit NotebookEdit; do deny "{\"tool_name\":\"$t\",\"tool_input\":{\"file_path\":\"$MP\"}}" || all_denied=0; done
deny "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"x\",\"path\":\"$MP\"}}" || all_denied=0
deny '{"tool_name":"Glob","tool_input":{"pattern":".specclaw/review-memory/*"}}' || all_denied=0
deny "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat $MP\"}}" || all_denied=0
check "AC-11 every file tool and a Bash read on the memory path are denied" '[ "$all_denied" = 1 ]'
check "AC-11 unrelated path and git add of the file are allowed" '! deny "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/p/a.py\"}}" && ! deny "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git add $MP\"}}"'
check "AC-11 deny reason names memory_query" 'printf "%s" "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$MP\"}}" | python3 "$GUARD" | grep -q memory_query'

# AC-12: MCP server over stdio.
cd "$TMP/r" || exit 1
mcp="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"memory_query","arguments":{"files":["a.py"]}}}' \
  | python3 "$PLUGIN_DIR/mcp/server.py")"
check "AC-12 initialize, tools/list (10 tools), memory_query call" 'python3 - "$mcp" <<"PY"
import json, sys
r = [json.loads(l) for l in sys.argv[1].splitlines()]
assert [x["id"] for x in r] == [1, 2, 3]
assert r[0]["result"]["protocolVersion"] == "2025-06-18"
assert len(r[1]["result"]["tools"]) == 10
assert "off by one" in r[2]["result"]["content"][0]["text"] and r[2]["result"]["isError"] is False
PY'

# AC-13: learn is dry-run by default; --apply writes; --import needs --apply.
mkdir -p .specclaw/changes/002-other
out_json "$MAJOR"; "$SR" run --change 002-other >/dev/null   # the same lesson in a second change → a learn candidate
"$SR" learn >/dev/null
check "AC-13 learn dry-run writes nothing" '[ ! -f .specclaw/review/rules/learned.md ]'
fp="$("$SR" learn | sed -nE 's/^- fp ([0-9a-f]+).*/\1/p' | head -1)"
"$SR" learn --apply "$fp" >/dev/null
check "AC-13 learn --apply writes learned.md and marks the lesson ruled" 'grep -q "\*\*L1\*\*" .specclaw/review/rules/learned.md && ! "$SR" learn | grep -q "$fp"'
printf '# Pitfalls\n- never X\n' > "$TMP/PITFALLS.md"
"$SR" learn --import "$TMP/PITFALLS.md" >/dev/null
check "AC-13 import is dry-run without --apply" '[ ! -f .specclaw/review/rules/imported-PITFALLS.md ]'
"$SR" learn --import "$TMP/PITFALLS.md" --apply >/dev/null
check "AC-13 import --apply copies with a source header" 'grep -q "imported by specclaw-review" .specclaw/review/rules/imported-PITFALLS.md'

# AC-14: stats.
st="$("$SR" stats)"
check "AC-14 stats prints median rounds and per-model rates" 'grep -q "median rounds" <<<"$st" && grep -q "model small-m" <<<"$st"'

# AC-15: lazy init is idempotent.
mkrepo "$TMP/r15"
"$SR" init >/dev/null; "$SR" init >/dev/null
check "AC-15 rules dir, memory dir, one .gitattributes line, claude rule" '[ -d .specclaw/review/rules ] && [ -d .specclaw/review-memory ] && [ "$(grep -c "review-memory" .gitattributes)" = 1 ] && [ -f .claude/rules/specclaw-review-memory.md ]'

# AC-16: core PR body carries the line only when the plugin is on PATH; docs carry the guarded step.
body_fn() { sed -n '/^build_pr_body() {/,/^}/p' "$REPO/plugins/specclaw/bin/specclaw-pr"; }
check "AC-16 specclaw-pr review line is guarded and appended to the Verdict line" 'body_fn | grep -q "command -v specclaw-review" && body_fn | grep -q "\*\*Verdict:\*\* \${verdict}\${review_line}"'
check "AC-16 azdo-pr carries the same guarded line" 'grep -q "command -v specclaw-review" "$REPO/plugins/specclaw-sync/bin/specclaw-azdo-pr"'
check "AC-16 lean+full verify/pr docs mention the guarded step" 'for f in skills/verify/SKILL.md skills/pr/SKILL.md references/full/verify.md references/full/pr.md; do grep -q "command -v specclaw-review" "$REPO/plugins/specclaw/$f" || exit 1; done'

# AC-17: packaging — both manifests, both marketplaces, one shared version.
check "AC-17 specclaw-review packaged at the shared version" 'python3 - "$REPO" <<"PY"
import glob, json, sys
r = sys.argv[1]
cl = json.load(open(r + "/plugins/specclaw-review/.claude-plugin/plugin.json"))
cx = json.load(open(r + "/plugins/specclaw-review/.codex-plugin/plugin.json"))
mk = json.load(open(r + "/.claude-plugin/marketplace.json"))["plugins"]
ag = json.load(open(r + "/.agents/plugins/marketplace.json"))["plugins"]
assert "specclaw-review" in [p["name"] for p in mk] and "specclaw-review" in [p["name"] for p in ag]
vs = {json.load(open(f))["version"] for f in glob.glob(r + "/plugins/*/.c*-plugin/plugin.json")} | {p["version"] for p in mk}
assert len(vs) == 1 and cl["version"] == cx["version"], vs
assert json.load(open(r + "/plugins/specclaw-review/.mcp.json"))["mcpServers"]["specclaw-review"]["command"] == "python3"
PY'

# AC-19..AC-22: passes, tools, live governance, docs visible. A stub backend logs each call's stdin and
# answers per pass (the design pass's instruction says "Focus ONLY on design").
mkrepo "$TMP/r19"
cat > "$TMP/stub.py" <<'PY'
import sys, json, os
d = sys.argv[1]; s = sys.stdin.read()
n = len([f for f in os.listdir(d) if f.startswith("call-")]) + 1
open(os.path.join(d, f"call-{n}.txt"), "w").write(s)
design = "Focus ONLY on design" in s
print(json.dumps([{"severity": "major", "rule": "D1" if design else "B1", "file": "a.py", "line": 3 if design else 2,
                   "message": ("[design] " if design else "") + "same issue", "scenario": "x", "in_delta": True},
                  {"severity": "major", "rule": "B1", "file": "README.md", "line": 1, "message": "doc", "scenario": "x"}]))
PY
mkdir -p "$TMP/calls"
printf 'presets: []\ngit:\n  base_branch: main\nreview:\n  backend: "python3 %s/stub.py %s/calls"\n  passes: [review, design]\n  governance: ["GOV*.md"]\n' "$TMP" "$TMP" > .specclaw/config.yaml
printf '# Governance\n- G1 first law\n' > GOV-law.md && printf '# Readme\nusage: helper_fn adds one\n' > README.md
printf 'def helper_fn(a):\n    return a + 3\n' > a.py && git add -A && git commit -qm "code + readme"
"$SR" run --change "$CH" >/dev/null
last="$RD/round-1.json"
check "AC-19 two passes, two backend calls, findings tagged and collapsed across passes" 'python3 - "$last" "$TMP/calls" <<"PY"
import json, os, sys
d = json.load(open(sys.argv[1])); calls = sorted(os.listdir(sys.argv[2]))
assert len(calls) == 2 and d["passes"] == ["review", "design"], (calls, d.get("passes"))
code = [f for f in d["findings"] if f["file"] == "a.py"]
assert len(code) == 1 and code[0]["pass"] in ("review", "design"), code
PY'
check "AC-19 two passes naming the same symbol in one file collapse even lines apart" 'python3 - "$PLUGIN_DIR/lib" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_core as rc
class C(rc.Config):
    def __init__(self): self.review = {}
f = [{"severity": "major", "rule": "B3", "file": "x.py", "line": 185, "message": "`load_rows` hides it", "scenario": "s", "pass": "review"},
     {"severity": "major", "rule": "B5", "file": "x.py", "line": 193, "message": "`load_rows(q)` returns newest", "scenario": "s", "pass": "design"},
     {"severity": "major", "rule": "B5", "file": "x.py", "line": 300, "message": "`other_fn` breaks", "scenario": "s", "pass": "design"}]
assert len(rc.calibrate(C(), f)) == 2
PY'
check "AC-24 severity: project keeps a scenario-less major and drops the scenario gate from the prompt" 'python3 - "$PLUGIN_DIR/lib" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_core as rc
class C(rc.Config):
    def __init__(self, review): self.review = review
f = lambda: [{"severity": "major", "rule": "law", "file": "x.py", "line": 1, "message": "m"}]
assert rc.calibrate(C({"severity": "project"}), f())[0]["severity"] == "major"
assert rc.calibrate(C({}), f())[0]["severity"] == "minor"
assert rc.calibrate(C({"governance": ["CLAUDE.md"]}), f())[0]["severity"] == "major"   # governance → project by default
assert rc.calibrate(C({"governance": ["CLAUDE.md"], "severity": "plugin"}), f())[0]["severity"] == "minor"
assert "REQUIRED" not in rc.build_prompt(C({"severity": "project"}), "d", {}, [], False, "x")
PY'
check "AC-20 default backend argv: tools, turns, system file, dontAsk; none → --tools \"\"" 'python3 - "$PLUGIN_DIR/lib" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_core as rc
class C(rc.Config):
    def __init__(self, review): self.review = review
a, inline = rc.backend_argv(C({"tools": "Read,Grep,Glob"}), "opus", "/s.md")
j = " ".join(a)
assert not inline and "--allowedTools Read,Grep,Glob" in j and "--max-turns 12" in j
assert "--append-system-prompt-file /s.md" in j and "--permission-mode dontAsk" in j and "Read(~/.claude/**)" in j
a, _ = rc.backend_argv(C({}), "haiku", "/s.md")
assert rc.parse_block("review:\n  models: { round: opus, final: \"sonnet\" }\n", "review")["models"] == {"round": "opus", "final": "sonnet"}
assert a[a.index("--tools") + 1] == "" and a[a.index("--max-turns") + 1] == "1"
PY'
check "AC-21 governance file is in the rulebook, read live" '"$SR" rules 2>/dev/null | grep -q "G1 first law" && printf "# Governance\n- G2 edited law\n" > GOV-law.md && "$SR" rules 2>/dev/null | grep -q "G2 edited law"'
check "AC-22 README hunk is in the reviewed diff; a README finding is capped at minor" 'grep -q "helper_fn adds one" "$TMP/calls/call-1.txt" && [ "$(field "$last" "[f[\"severity\"] for f in d[\"findings\"] if f[\"file\"]==\"README.md\"][0]")" = minor ]'
git checkout -q -- GOV-law.md && git checkout -q -b docs-only main && echo "more" >> NOTES.md && git add -A && git commit -qm docs
check "AC-22 a docs-only change classifies as skip" '[ "$("$SR" classify | head -1)" = skip ]'

# Review fixes (044 verify): option injection, fail-closed parsing, rebased final pass, one count per change.
mkrepo "$TMP/rf"
check "since that looks like an option is refused before git sees it" '! "$SR" classify --since "--output=$TMP/pwned" >/dev/null 2>&1 && [ ! -e "$TMP/pwned" ]'
out_json '[{"severity":"critical","file":"a.py","line":1,"message":"x","scenario":"s"},{"severity":"major","message":"no file","scenario":"s"}]'
"$SR" run --change "$CH" >/dev/null; rc=$?
check "an unknown severity or a missing file is kept (fail closed), never dropped" '[ "$rc" = 1 ] && [ "$(field "$RD/round-1.json" "\",\".join(sorted(f[\"severity\"] for f in d[\"findings\"]))")" = "blocker,major" ]'
"$SR" run --change "$CH" >/dev/null
check "a finding still open next round is not counted again in memory" 'python3 - "$PLUGIN_DIR/lib" "$TMP/rf/.specclaw/review-memory" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_memory as m
assert all(e["count"] == 1 for e in m.load(sys.argv[2])), m.load(sys.argv[2])
PY'
out_json '[]'; "$SR" run --change "$CH" --final >/dev/null
git commit -q --amend -m "rewritten" --allow-empty
v="$("$SR" verdict --change "$CH")"; vrc=$?
check "a final pass lost to a rebase is exit 1 with a reason, not exit 2" '[ "$vrc" = 1 ] && grep -q "not in HEAD" <<<"$v"'
check "the guard allows the specclaw-review-memory rule file and guards a configured memory_dir" '! deny "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/p/.claude/rules/specclaw-review-memory.md\"}}" && printf "review:\n  memory_dir: .specclaw/lessons\n" > .specclaw/config.yaml && deny "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/p/.specclaw/lessons/findings.jsonl\"}}"'

# AC-25/AC-26: discover is a read-only scan of the repo's own governance.
mkrepo "$TMP/r25"
mkdir -p docs/adr docs/plans tests/fixtures/x node_modules/pkg .specclaw/changes/old .claude/skills/s
printf '# Law\nA not-run check is a blocker.\n' > CLAUDE.md
printf '# Agents\n' > AGENTS.md
printf '# Conventions\n' > docs/plans/CODE-CONVENTIONS.md
printf '# Pitfalls\n' > docs/plans/REVIEW-PITFALLS.md
printf '# ADR 1\n' > docs/adr/0001-x.md
for f in tests/fixtures/x/CLAUDE.md node_modules/pkg/CLAUDE.md .specclaw/changes/old/CLAUDE.md .claude/skills/s/AGENTS.md; do echo x > "$f"; done
printf 'pitfalls = 1\n' > review_pitfalls.py
git add -A && git -c core.autocrlf=false commit -qm docs
before="$(git status --porcelain | wc -l)"
disc="$("$SR" discover)"
check "AC-25 governance found by category; fixtures, vendor, change records, skills and code excluded" 'python3 - "$disc" <<"PY"
import sys; d = sys.argv[1]
for p in ("- CLAUDE.md", "- AGENTS.md", "- docs/plans/CODE-CONVENTIONS.md", "- docs/plans/REVIEW-PITFALLS.md", "- docs/adr/0001-x.md"):
    assert p in d, p
for p in ("fixtures", "node_modules", "changes/old", ".claude/skills", "review_pitfalls.py"):
    assert p not in d, p
assert d.index("## decisions") < d.index("docs/adr/0001-x.md")
PY'
check "AC-25 severity flagged; suggested block names governance but not ADRs; nothing written" 'grep -q "defines severity" <<<"$disc" && grep -q "\"CLAUDE.md\"" <<<"$disc" && ! grep -q "\"docs/adr" <<<"$disc" && [ "$(git status --porcelain | wc -l)" = "$before" ]'
printf 'presets: []\ngit:\n  base_branch: main\nreview:\n  governance_budget: 10\n' > .specclaw/config.yaml
check "AC-26 over budget warns; --json is valid JSON" '"$SR" discover | grep -q WARNING && "$SR" discover --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"over_budget\"] is True"'

# 064 AC-1: verdict --head binds the clean verdict to one exact SHA (no records-only drift).
mkrepo "$TMP/h1"
out_json '[]'; "$SR" run --change "$CH" --final >/dev/null
fh="$(git rev-parse HEAD)"
o="$("$SR" verdict --change "$CH" --head "$fh")"; rc=$?
check "064 AC-1 --head at the final-pass SHA exits 0 and prints the final round file" '[ "$rc" = 0 ] && [ "$(sed -n 2p <<<"$o")" = "$RD/round-1.json" ]'
check "064 AC-1 --head at another SHA exits 1" '! "$SR" verdict --change "$CH" --head "$(git rev-parse HEAD~1)" >/dev/null'
git add -A && git commit -qm records
check "064 AC-1 records-only commit: plain verdict OK, --head at the new HEAD exits 1" '"$SR" verdict --change "$CH" >/dev/null && ! "$SR" verdict --change "$CH" --head "$(git rev-parse HEAD)" >/dev/null'
out_json "$MAJOR"; "$SR" run --change "$CH" --final >/dev/null
check "064 AC-1 an open final pass at the given SHA exits 1" '! "$SR" verdict --change "$CH" --head "$(git rev-parse HEAD)" >/dev/null'

# 064 AC-4: finding class is normalised; follow-ups carry it.
check "064 AC-4 class normalised: Data Loss -> data-loss, missing/unknown -> other" 'python3 - "$PLUGIN_DIR/lib" <<"PY"
import sys; sys.path.insert(0, sys.argv[1]); import review_core as rc
class C(rc.Config):
    def __init__(self): self.review = {}
f = rc.calibrate(C(), [{"severity": "minor", "rule": "B1", "file": "x.py", "line": 1, "message": "a", "class": "Data Loss"},
                       {"severity": "minor", "rule": "B2", "file": "y.py", "line": 1, "message": "b"},
                       {"severity": "minor", "rule": "B3", "file": "z.py", "line": 1, "message": "c", "class": "style"},
                       {"severity": "minor", "rule": "B4", "file": "w.py", "line": 1, "message": "d", "class": "SECURITY"}])
assert [x["class"] for x in f] == ["data-loss", "other", "other", "security"], [x["class"] for x in f]
C.release_gate = {"block_on": ["Data Loss", "'law'"]}
assert C().block_on == ["data-loss", "law"], C().block_on
C.release_gate = {"block_on": ["securty"]}
try:
    C().block_on; raise AssertionError("a misspelt gate class must be refused, not ignored")
except rc.ReviewError:
    pass
C.release_gate = {}
assert C().block_on == ["law", "security", "data-loss"]
PY'
mkrepo "$TMP/c4"
out_json '[{"severity":"minor","rule":"B10","file":"a.py","line":1,"message":"naming","class":"law","in_delta":true}]'
"$SR" run --change "$CH" >/dev/null
check "064 AC-4 the follow-up line carries class:" 'grep -q "class:law -->" ".specclaw/changes/$CH/follow-ups.md"'

# 064 AC-5: fast track — one final round, only gate-class blockers block, the rest goes to debt.md once.
ftcfg() { printf 'presets: []\ngit:\n  base_branch: main\nreview:\n  backend: "cat %s.out.json"\n  fast_track: %s\n%s' "$(git rev-parse --show-toplevel)" "$1" "${2:-}" > .specclaw/config.yaml; }
mkrepo "$TMP/ft"
ftcfg all
FT='[{"severity":"major","rule":"S1","file":"a.py","line":2,"message":"token logged","scenario":"s","class":"security","in_delta":true},
 {"severity":"blocker","rule":"B2","file":"a.py","line":1,"message":"crash on none","scenario":"s","class":"other","in_delta":true},
 {"severity":"minor","rule":"B10","file":"a.py","line":1,"message":"naming","in_delta":true}]'
out_json "$FT"; "$SR" run --change "$CH" >/dev/null; rc=$?
check "064 AC-5 fast track: non-gate findings exit 0, round is final, all three land in debt.md" '[ "$rc" = 0 ] && [ "$(field "$RD/round-1.json" "d[\"final\"]")" = True ] && [ "$(grep -c "^- \[ \]" .specclaw/debt.md)" = 3 ] && grep -q "class:security -->" .specclaw/debt.md'
check "064 AC-5 fast track: nothing goes to follow-ups.md; verdict is clean" '[ ! -f ".specclaw/changes/$CH/follow-ups.md" ] && "$SR" verdict --change "$CH" >/dev/null'
"$SR" run --change "$CH" >/dev/null
check "064 AC-5 a re-run does not duplicate debt lines" '[ "$(grep -c "^- \[ \]" .specclaw/debt.md)" = 3 ]'
out_json '[{"severity":"blocker","rule":"S2","file":"a.py","line":2,"message":"sql injection","scenario":"s","class":"security","in_delta":true}]'
"$SR" run --change "$CH" >/dev/null; rc=$?
check "064 AC-5 fast track: a security blocker exits 1 and is not written to debt" '[ "$rc" = 1 ] && ! grep -q "sql injection" .specclaw/debt.md'
ftcfg all "$(printf 'release_gate:\n  block_on: [law]\n')"
"$SR" run --change "$CH" >/dev/null; rc=$?
check "064 AC-5 release_gate.block_on: [law] makes a security blocker debt, not a block" '[ "$rc" = 0 ] && grep -q "sql injection" .specclaw/debt.md'
out_json '[{"severity":"blocker","rule":"B7","file":"a.py","line":2,"message":"unlabelled crash","scenario":"s","in_delta":true}]'
"$SR" run --change "$CH" >/dev/null; rc=$?
check "064 AC-5 fast track: a blocker with no class stays blocking" '[ "$rc" = 1 ] && ! grep -q "unlabelled crash" .specclaw/debt.md'
out_json '[{"severity":"major","rule":"B8","file":"a.py","line":2,"message":"unlabelled major","scenario":"s","in_delta":true}]'
"$SR" run --change "$CH" >/dev/null
check "064 AC-5 an unlabelled major goes to debt as class:unclassified, for the release gate to block" 'grep -q "unlabelled major.*class:unclassified -->" .specclaw/debt.md'
out_json '[{"severity":"major","rule":"S9","file":"a.py","line":2,"message":"leaks\n\n  the token","scenario":"s","class":"security","in_delta":true}]'
"$SR" run --change "$CH" >/dev/null
check "064 AC-5 a multi-line message is one debt line that keeps its class marker" 'grep -q "^- \[ \] \[security major S9\] .*leaks the token .*class:security -->$" .specclaw/debt.md'
sed -i.bak "s/^- \[ \] \(.*leaks the token\)/- [x] \1/" .specclaw/debt.md && rm -f .specclaw/debt.md.bak
"$SR" run --change "$CH" >/dev/null
check "064 AC-5 a ticked item that recurs is listed again as open" '[ "$(grep -c "leaks the token" .specclaw/debt.md)" = 2 ] && grep -q "^- \[ \] .*leaks the token" .specclaw/debt.md'
ftcfg all "$(printf 'release_gate:\n  block_on: [securty]\n')"
"$SR" run --change "$CH" >/dev/null 2>&1; rc=$?
check "064 AC-5 fast track with a misspelt block_on class refuses to run (exit 2)" '[ "$rc" = 2 ]'
mkrepo "$TMP/ft2"
ftcfg "[some-other-change]"
out_json "$FT"; "$SR" run --change "$CH" >/dev/null; rc=$?
check "064 AC-5 fast track off for this change: unchanged loop (exit 1, not final, no debt.md)" '[ "$rc" = 1 ] && [ "$(field "$RD/round-1.json" "d[\"final\"]")" = False ] && [ ! -f .specclaw/debt.md ]'

# 064 AC-7: both CI templates run the verdict and post the status only through the --head gate.
for t in github-actions.yml azure-pipelines.yml; do
  check "064 AC-7 $t: verdict step, status gated by verdict --head, review-loop context" 'f="$PLUGIN_DIR/ci/$t"; grep -q "verdict --change \"\$CHANGE\" --check-head" "$f" && grep -q "if.*verdict --change \"\$CHANGE\" --head \"\$HEAD_SHA\"" "$f" && grep -q "review-loop" "$f"'
done
check "064 AC-7 templates are valid YAML (when PyYAML is installed)" 'python3 -c "import yaml" 2>/dev/null || exit 0; for t in "$PLUGIN_DIR"/ci/*.yml; do python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1]))" "$t" || exit 1; done'

echo
[ "$FAILS" -eq 0 ] && echo "All specclaw-review tests passed." || echo "$FAILS failure(s)."
exit $((FAILS > 0))
