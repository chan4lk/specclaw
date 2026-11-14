#!/usr/bin/env bash
# Change 065: hooks/context-gate (the PreToolUse context cap) and bin/specclaw-budget (roles, set,
# estimate, brief, record, handover), against transcript fixtures in a temp tree.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$HERE/hooks/context-gate"
BUDGET="$HERE/bin/specclaw-budget"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT
export SPECCLAW_GATE_LOG_DIR="$TMP/log" SPECCLAW_TRANSCRIPTS="$TMP/projects"
fail=0
ok() { echo "PASS: $1"; }
no() { fail=1; echo "FAIL: $1"; }

# A project: config.yaml with a decoy `context:` key in another block above budget:, so a whole-file
# read would find it. The decoy is the test; do not tidy it away.
P="$TMP/proj"
mkdir -p "$P/.specclaw/changes/001-x" "$P/src"
cat > "$P/.specclaw/config.yaml" <<'EOF'
models:
  builder-backend:
    context: 123456
budget:
  gate: GATE
  roles:
    code-reviewer:
      context: 100000   # a comment survives set
review:
  timeout_seconds: 10
EOF
gate() { sed -i.bak "s/^  gate: .*/  gate: $1/" "$P/.specclaw/config.yaml" && rm -f "$P/.specclaw/config.yaml.bak"; }
gate warn

# transcript <agent> <context> [prompt]: a session file and the agent's own under subagents/.
transcript() {
  local dir="$SPECCLAW_TRANSCRIPTS/p/sess/subagents"
  mkdir -p "$dir"
  : > "$SPECCLAW_TRANSCRIPTS/p/sess.jsonl"
  python3 - "$dir/agent-$1.jsonl" "$2" "${3:-do the task}" <<'EOF'
import json, sys
path, context, prompt = sys.argv[1], int(sys.argv[2]), sys.argv[3]
usage = lambda n: {"input_tokens": 10, "cache_creation_input_tokens": 0, "cache_read_input_tokens": n - 10, "output_tokens": 5}
rows = [{"type": "user", "message": {"role": "user", "content": prompt}},
        {"type": "assistant", "message": {"model": "m", "usage": usage(context + 5000)}},
        {"type": "assistant", "message": {"model": "m", "usage": usage(context)}}]
open(path, "w").write("".join(json.dumps(r) + "\n" for r in rows) + '{"type":"assistant","mess')
EOF
}
# event <agent|""> <type> <tool> <command>: one PreToolUse event on stdout.
event() {
  python3 -c 'import json, sys
a, t, tool, cmd, sess, cwd = sys.argv[1:]
e = {"session_id": "s1", "transcript_path": sess, "cwd": cwd, "hook_event_name": "PreToolUse",
     "tool_name": tool, "tool_input": {"command": cmd} if tool == "Bash" else {"file_path": "x"}}
if a: e.update(agent_id=a, agent_type=t)
print(json.dumps(e))' "$1" "$2" "$3" "$4" "$SPECCLAW_TRANSCRIPTS/p/sess.jsonl" "$P"
}
run() { OUT="$(event "$@" | "$GATE" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }
silent() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }
has() { python3 -c 'import json, sys; d = json.loads(sys.argv[1]); assert sys.argv[2] in d["systemMessage"], d' "$OUT" "$1" 2>/dev/null; }

# ── AC-1 roles --json ─────────────────────────────────────────────────────────────────────────
r="$("$BUDGET" roles --json "$P/.specclaw" 2>/dev/null)"
if python3 -c 'import json, sys; d = json.loads(sys.argv[1])
assert set(d) == {"builder-backend", "builder-frontend", "code-reviewer", "general"}, d
assert d["builder-backend"] == {"context": 200000, "default": 200000, "min": 100000, "max": 400000, "source": "default"}, d
assert d["code-reviewer"] == {"context": 100000, "default": 150000, "min": 75000, "max": 300000, "source": "config"}, d' "$r"; then
  ok "roles --json: four roles, config override is source config, the decoy context: in models: is not read"
else no "roles --json: $r"; fi

# ── AC-2 set ──────────────────────────────────────────────────────────────────────────────────
cp "$P/.specclaw/config.yaml" "$TMP/before"
"$BUDGET" set "$P/.specclaw" builder-frontend 300000 && "$BUDGET" set "$P/.specclaw" code-reviewer 90000
diff "$TMP/before" "$P/.specclaw/config.yaml" > "$TMP/d"
if grep -q '^> *builder-frontend:$' "$TMP/d" && grep -q '^> *context: 300000$' "$TMP/d" \
   && grep -q '^>       context: 90000   # a comment survives set$' "$TMP/d" && [ "$(grep -c '^[<>]' "$TMP/d")" -eq 4 ] \
   && "$BUDGET" roles --json "$P/.specclaw" | grep -q '"builder-frontend": {"context": 300000'; then
  ok "set writes inside budget: only, adds a missing role, keeps a comment, and roles reads it back"
else no "set diff: $(cat "$TMP/d")"; fi
cp "$P/.specclaw/config.yaml" "$TMP/before"
"$BUDGET" set "$P/.specclaw" nosuch 100000 2>/dev/null; a=$?
"$BUDGET" set "$P/.specclaw" general 99999 2>/dev/null; b=$?
"$BUDGET" set "$P/.specclaw" general 400001 2>/dev/null; c=$?
"$BUDGET" set "$P/.specclaw" general 2>/dev/null; d=$?
"$BUDGET" set "$P/.specclaw" general abc 2>/dev/null; e=$?
if [ "$a$b$c$d$e" = 11122 ] && cmp -s "$TMP/before" "$P/.specclaw/config.yaml"; then
  ok "set refuses an unknown role and out-of-range values with exit 1, bad arguments with exit 2, writes nothing"
else no "set refusals: $a$b$c$d$e"; fi
T="$TMP/template/.specclaw"; mkdir -p "$T"; cp "$HERE/templates/config.yaml" "$T/config.yaml"
"$BUDGET" set "$T" builder-backend 150000
if [ "$(sed -n '/^budget:/,/^[a-z]/p' "$T/config.yaml" | grep -A2 '^  roles:  *# set with')" = "$(printf '  roles:                        # set with `specclaw-budget set .specclaw <role> <n>`; see `roles --json`\n    builder-backend:\n      context: 150000')" ] \
   && [ -z "$(find "$T" -name '.config.yaml.*')" ]; then
  ok "set on the shipped template turns roles: {} into a map, keeps its comment, leaves no temp file"
else no "set on the template: $(sed -n '/^budget:/,/^# Brown/p' "$T/config.yaml")"; fi
Q="$TMP/noblock/.specclaw"; mkdir -p "$Q"; printf 'models:\n  coding: x' > "$Q/config.yaml"
"$BUDGET" set "$Q" general 150000
if [ "$(cat "$Q/config.yaml")" = "$(printf 'models:\n  coding: x\nbudget:\n  roles:\n    general:\n      context: 150000')" ]; then
  ok "set creates the budget: block when the config has none"
else no "set without a block: $(cat "$Q/config.yaml")"; fi

# ── AC-3 silent paths ─────────────────────────────────────────────────────────────────────────
transcript a1 190000
run "" "" Edit x; silent && ok "a main-session call exits 0 in silence" || no "main session: $RC $OUT $ERR"
transcript a1 170000
run a1 general-purpose Edit x; silent && ok "an agent under 90% of its cap exits 0 in silence" || no "under cap: $RC $OUT $ERR"
transcript a1 190000
gate off; run a1 general-purpose Edit x; silent && ok "gate: off exits 0 in silence over the cap" || no "off: $RC $OUT $ERR"
gate warn
mkdir -p "$TMP/notaproject"
OUT="$(event a1 general-purpose Edit x | sed "s#\"cwd\": \"[^\"]*\"#\"cwd\": \"$TMP/notaproject\"#" | "$GATE" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "no .specclaw/config.yaml exits 0 in silence" || no "no config: $RC $OUT"

# ── AC-4 warn ─────────────────────────────────────────────────────────────────────────────────
rm -rf "$SPECCLAW_GATE_LOG_DIR"
run a1 general-purpose Edit x
if [ "$RC" -eq 0 ] && has "at 190k of 200k" && python3 -c 'import json, sys; d = json.loads(sys.argv[1])
assert "specclaw-budget handover" in d["hookSpecificOutput"]["additionalContext"], d' "$OUT" \
   && [ "$(wc -l < "$SPECCLAW_GATE_LOG_DIR/gate.jsonl")" -eq 1 ] && grep -q '"decision": "note"' "$SPECCLAW_GATE_LOG_DIR/gate.jsonl"; then
  ok "warn at 90%: exit 0, a systemMessage, the hand-off steps as additionalContext, one log line"
else no "warn: $RC $OUT $ERR"; fi

# ── AC-5 block ────────────────────────────────────────────────────────────────────────────────
gate block
run a1 general-purpose Bash 'git add -A && git commit -m "fix: a; b && rm -rf c"'; [ "$RC" -eq 0 ] && has "hand off" && ok "block: git add && git commit (a message holding ; && rm) passes with the note" || no "block commit: $RC $OUT $ERR"
run a1 general-purpose Bash 'specclaw-budget handover .specclaw 001-x T1 finish the tests'; [ "$RC" -eq 0 ] && ok "block: specclaw-budget handover passes" || no "block handover: $RC $ERR"
for c in 'git commit -m x 2>&1' 'git status 2>/dev/null' 'git log --oneline | head -5' 'git diff >&2' 'git commit -m x &>/dev/null' 'git add -A 2>> /dev/null' 'git log 2>&1 | head -5' 'git status | tail -3' 'cd /tmp && git -C /tmp add -A'; do
  run a1 general-purpose Bash "$c"; [ "$RC" -eq 0 ] && ok "block: '$c' passes (fd duplication, /dev/null, head and tail)" || no "block $c: $RC $ERR"
done
for c in Edit 'Bash:rm -rf x' 'Bash:git add . && rm x' 'Bash:git commit -m ok; curl x' 'Bash:git add -A &>/dev/null & rm x' 'Bash:git log | xargs rm' 'Bash:git log > f' 'Bash:git status 1>out' 'Bash:git log 2>> e' 'Bash:cat < in' 'Bash:git commit -m x &>/tmp/c.log' 'Bash:git log > f; rm x' 'Bash:git log >/dev/nullx' 'Bash:git log >&2x' 'Bash:git log 2>&1x' 'Bash:git log >&file' 'Bash:git log | sort -o f' 'Bash:git diff --output=f' 'Bash:git log --output f' 'Bash:git log | grep x' 'Bash:cat f'; do
  case "$c" in Bash:*) run a1 general-purpose Bash "${c#Bash:}" ;; *) run a1 general-purpose "$c" x ;; esac
  [ "$RC" -eq 2 ] && [[ "$ERR" == *"specclaw-budget handover"* ]] && ok "block denies '$c' with exit 2 and the hand-off steps" || no "block $c: $RC $OUT $ERR"
done

# ── AC-6 role and cap ─────────────────────────────────────────────────────────────────────────
gate block
transcript a2 170000
run a2 specclaw:code-reviewer Edit x; [ "$RC" -eq 2 ] && ok "specclaw:code-reviewer is the code-reviewer role (cap 100k from config: 170k denied)" || no "reviewer role: $RC $ERR"
run a2 my-own-agent Edit x; [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "an unknown agent type is general (200k: 170k passes)" || no "general: $RC $OUT"
transcript a3 170000 'specclaw budget: role=builder-backend context=20000
do T1'
run a3 general-purpose Edit x; [ "$RC" -eq 2 ] && [[ "$ERR" == *"builder-backend agent is at 170k of its 100k"* ]] && ok "a stated context=20000 is clamped up to the role's minimum 100k, and the stated role wins" || no "clamp low: $RC $ERR"
transcript a3 170000 'specclaw budget: role=builder-frontend context=900000'
run a3 general-purpose Edit x; [ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "a stated context=900000 is clamped down to 400k (170k passes)" || no "clamp high: $RC $OUT $ERR"
for v in '70k' '70,000' '~70000' '7e4' '70000tokens'; do
  transcript a3 170000 "specclaw budget: role=builder-backend context=$v"
  run a3 general-purpose Edit x; [ "$RC" -eq 0 ] && has "context='$v' is not a whole number" && ok "a stated context=$v fails loud, never falls back in silence" || no "bad stated $v: $RC $OUT $ERR"
done

# ── AC-7 fail open ────────────────────────────────────────────────────────────────────────────
rm -rf "$SPECCLAW_GATE_LOG_DIR"
OUT="$(printf '{"agent_id": "a1", "session_' | "$GATE" 2>/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && has "context gate error" && grep -q '"error": "JSONDecodeError"' "$SPECCLAW_GATE_LOG_DIR/gate.jsonl" && ok "a torn event fails open: exit 0, a systemMessage, a log line" || no "torn: $RC $OUT"
printf '{"type":"assistant","message":{"usage":{"input_tokens":"x"}}}\n{"type":"user"}\n' > "$SPECCLAW_TRANSCRIPTS/p/sess/subagents/agent-a4.jsonl"
run a4 general-purpose Edit x; [ "$RC" -eq 0 ] && has "TypeError" && has "the call went through" && ok "an unreadable transcript fails open and loud" || no "bad transcript: $RC $OUT $ERR"
run '../x' general-purpose Edit x; [ "$RC" -eq 0 ] && has "not a plain id" && ok "an agent_id that is not a plain id fails open" || no "agent id: $RC $OUT"
gate bogus
run a1 general-purpose Edit x; [ "$RC" -eq 0 ] && has "running on warn" && ok "a bad gate value runs on warn and says so" || no "bad gate: $RC $OUT $ERR"
gate warn
printf 'budget:\n  roles:\n    general:\n      context:\n    builder-backend:\n      context: 5\n' > "$Q/config.yaml"
r="$("$BUDGET" roles --json "$Q" 2>"$TMP/err")"; rc=$?
[ "$rc" -eq 0 ] && [[ "$r" == *'"general": {"context": 200000'* ]] && grep -q 'general.context' "$TMP/err" && grep -q 'builder-backend.context' "$TMP/err" \
  && ok "a blank or out-of-range context is a warning and the default stands" || no "blank context ($rc): $r $(cat "$TMP/err")"
run nosuchagent general-purpose Edit x; [ "$RC" -eq 0 ] && has "no subagent transcript" && ok "a missing subagent transcript fails open and loud, never silent" || no "missing transcript: $RC $OUT"

# ── AC-8 estimate, brief, record, handover, timer ─────────────────────────────────────────────
head -c 22000 /dev/zero | tr '\0' a > "$P/src/big.ts"
cat > "$P/.specclaw/changes/001-x/tasks.md" <<'EOF'
- [ ] `T1` — small
  - Files: `src/big.ts`, src/new.ts
  - Kind: frontend
- [ ] `T2` — sized by the planner
  - Files: src/big.ts
  - Context: 70000
- [ ] `T3` — no files
- [ ] `T4` — no files, but sized
  - Context: 90000
EOF
out="$("$BUDGET" estimate "$P/.specclaw" 001-x)"; rc=$?
if [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | head -2)" = "$(printf 'T1 read=36000 context=36000\nT2 read=36000 context=70000')" ] \
   && [[ "$out" == *"over 60000: T2, T4; split it"* ]]; then
  ok "estimate: read = 26000 + chars/2.2 (a missing file counts 0), Context: wins, exit 1 naming T2 and T4 (sized with no Files:)"
else no "estimate ($rc): $out"; fi
b1="$("$BUDGET" brief "$P/.specclaw" 001-x T1)"; b2="$("$BUDGET" brief "$P/.specclaw" 001-x T2)"
if [ "$b1" = "$(printf 'subagent_type: specclaw:builder-frontend\nspecclaw budget: role=builder-frontend')" ] \
   && [ "$b2" = "$(printf 'subagent_type: specclaw:builder-backend\nspecclaw budget: role=builder-backend context=70000')" ]; then
  ok "brief routes Kind frontend to builder-frontend, anything else to builder-backend, with the budget line"
else no "brief: $b1 / $b2"; fi
"$BUDGET" brief "$P/.specclaw" 001-x T9 2>/dev/null; [ $? -eq 1 ] && ok "brief of an unknown task exits 1" || no "brief unknown task"
"$BUDGET" record "$P/.specclaw" 001-x T9 a1 2>/dev/null; [ $? -eq 1 ] && ok "record of an unknown task exits 1" || no "record unknown task"
mkdir -p "$TMP/empty/.specclaw/changes/001-x" "$TMP/dirconf/config.yaml/x"; cp "$P/.specclaw/changes/001-x/tasks.md" "$TMP/empty/.specclaw/changes/001-x/"
for d in "$TMP/nowhere" "$TMP/empty/.specclaw" "$TMP/dirconf"; do
  "$BUDGET" roles --json "$d" >/dev/null 2>&1; a=$?; "$BUDGET" brief "$d" 001-x T1 >/dev/null 2>&1; b=$?
  [ "$a$b" = 11 ] && ok "roles --json and brief exit 1 with no config.yaml file (${d#"$TMP"/}), never defaults passed off as a read" || no "no config $d: $a$b"
done
mkdir -p "$P/.specclaw/changes/002-y"
for v in '70,000' '70000 tokens' '~70000' '7e4' '70k'; do
  printf -- '- [ ] `T1` — a\n  - Files: src/big.ts\n  - Context: %s\n' "$v" > "$P/.specclaw/changes/002-y/tasks.md"
  o1="$("$BUDGET" estimate "$P/.specclaw" 002-y 2>&1)"; r1=$?; o2="$("$BUDGET" brief "$P/.specclaw" 002-y T1 2>&1)"; r2=$?
  o3="$("$BUDGET" record "$P/.specclaw" 002-y T1 a1 2>&1)"; r3=$?
  [ "$r1$r2$r3" = 111 ] && [[ "$o1" == *"T1: Context: '$v' is not a whole number"* ]] && [[ "$o2$o3" == *"'$v' is not a whole number"*"'$v' is not a whole number"* ]] \
    && ok "Context: '$v' is refused by estimate (naming T1), brief and record" || no "Context '$v' ($r1$r2$r3): $o1 / $o2 / $o3"
done
[ ! -f "$P/.specclaw/changes/002-y/timeline.jsonl" ] && ok "a refused record writes no line" || no "refused record wrote"
"$BUDGET" record "$P/.specclaw" 001-x T2 a1 >/dev/null && "$BUDGET" record "$P/.specclaw" 001-x T1 zz >/dev/null \
  && "$BUDGET" handover "$P/.specclaw" 001-x T2 finish the parser tests
TL="$P/.specclaw/changes/001-x/timeline.jsonl"
if python3 -c 'import json, sys; rows = [json.loads(l) for l in open(sys.argv[1])]
assert [r["kind"] for r in rows] == ["task_context", "task_context", "handover"], rows
assert rows[0]["estimate"] == 70000 and rows[0]["peak"] == 195000 and rows[0]["agent"] == "a1", rows[0]
assert rows[0]["transcript"] == "found" and rows[0]["skipped"] == 0, rows[0]
assert rows[1]["estimate"] is None and rows[1]["peak"] is None and rows[1]["transcript"] == "missing", rows[1]
assert rows[2]["task"] == "T2" and rows[2]["next"] == "finish the parser tests" and "at" in rows[2], rows[2]' "$TL"; then
  ok "record appends estimate vs transcript peak (null when none), handover appends its line"
else no "timeline: $(cat "$TL")"; fi
"$HERE/bin/specclaw-timer" start "$P/.specclaw" 001-x build --kind phase >/dev/null 2>&1
"$HERE/bin/specclaw-timer" stop "$P/.specclaw" 001-x build >/dev/null 2>&1
err="$("$HERE/bin/specclaw-timer" report "$P/.specclaw" 001-x 2>&1 >/dev/null)"
[[ "$err" != *unparseable* ]] && ok "specclaw-timer report skips handover and task_context lines" || no "timer: $err"

# ── AC-9 wiring ───────────────────────────────────────────────────────────────────────────────
grep -q 'hooks/context-gate' "$HERE/hooks/mod.json" && python3 -c 'import json, sys; assert "PreToolUse" in json.load(open(sys.argv[1]))["hooks"]' "$HERE/hooks/mod.json" \
  && ! grep -q 'context-gate' "$HERE/hooks/hooks.json" && ok "PreToolUse context-gate is in mod.json and not in hooks.json (Codex)" || no "registration"
grep -q '^model: opus$' "$HERE/agents/builder-backend.md" && grep -q '^model: sonnet$' "$HERE/agents/builder-frontend.md" \
  && ok "builder-backend runs on opus, builder-frontend on sonnet" || no "builder agents"
grep -q 'run-context-gate-tests.sh' "$HERE/../../.github/workflows/ci.yml" && ok "this suite is registered in ci.yml" || no "ci.yml registration"

(( fail == 0 )) && echo "R065 the context gate holds subagents to their role's cap and fails open"
exit "$fail"
