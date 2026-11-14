#!/usr/bin/env python3
"""specclaw-review MCP server: stdio JSON-RPC 2.0, stdlib only, no network.

The single sanctioned door to review memory for agents. Every tool calls the same
core library as the CLI, so behaviour is identical.
"""
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lib"))
import review_core as rc  # noqa: E402
import review_memory as mem  # noqa: E402

PROTOCOL = "2025-06-18"


def _obj(props, required=()):
    return {"type": "object", "properties": props, "required": list(required)}


S = {"type": "string"}
TOOLS = {
    "review_rules": ("Resolved review rulebook: base + packs + repo rules + overrides.", _obj({})),
    "review_classify": ("Classify the change (or the commits since a sha) as skip or review.", _obj({"since": S})),
    "review_run": ("Run one review round. status clean|open|escalate|not_run|skipped.",
                   _obj({"change": S, "since": S, "final": {"type": "boolean"}}, ["change"])),
    "review_verdict": ("Derived verdict line; ok=true only when clean with a final pass at HEAD.",
                       _obj({"change": S}, ["change"])),
    "memory_query": ("Top lessons for the given files, bounded by a token budget. The ONLY way to read review memory.",
                     _obj({"files": {"type": "array", "items": S}, "budget": {"type": "integer"},
                           "k": {"type": "integer"}}, ["files"])),
    "memory_put": ("Record lessons (rule, file, message, severity). Repeats bump a count.",
                   _obj({"findings": {"type": "array", "items": {"type": "object"}}, "change": S}, ["findings"])),
    "memory_compact": ("Drop retired/stale entries and enforce the size cap.", _obj({})),
    "learn_propose": ("Dry-run: recurring lessons proposed as repo rules (human approves before apply).", _obj({})),
    "review_discover": ("Read-only scan for the repo's own review governance; suggests a review config.", _obj({})),
    "review_stats": ("Rounds per change, time to clean, blocker/major per round by model.", _obj({})),
}


def cfg():
    return rc.Config(rc.find_root(os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()))


def call(name, args):
    c = cfg()
    if name == "review_rules":
        book, notes = rc.rulebook(c)
        return "\n".join(notes + [book])
    if name == "review_classify":
        return json.dumps(rc.classify(c, args.get("since")), indent=1)
    if name == "review_run":
        rec = rc.run_round(c, args["change"], args.get("since"), bool(args.get("final")))
        keep = {k: rec[k] for k in ("round", "status", "model", "head", "counts", "findings", "fix_proof", "error") if k in rec}
        return json.dumps(keep, indent=1)
    if name == "review_verdict":
        code, line = rc.verdict(c, args["change"])
        return json.dumps({"ok": code == 0, "line": line})
    if name == "memory_query":
        return mem.query(c.mem_dir, args.get("files") or [], int(args.get("budget") or c.num("memory_budget", 1500)),
                         int(args.get("k") or c.num("memory_k", 10))) or "(no lessons for these files)"
    if name == "memory_put":
        rc.ensure(c)
        return json.dumps(mem.put(c.mem_dir, args.get("findings") or [], args.get("change", "")))
    if name == "memory_compact":
        return json.dumps(mem.compact(c.mem_dir, c.root, c.num("decay_days", 180), c.num("max_entries", 2000)))
    if name == "learn_propose":
        return rc.learn_propose(c)
    if name == "review_discover":
        return rc.discover_text(rc.discover(c))
    if name == "review_stats":
        return rc.stats(c)
    raise rc.ReviewError(f"unknown tool {name}")


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if mid is None:
        return None
    if method == "initialize":
        ver = (msg.get("params") or {}).get("protocolVersion") or PROTOCOL
        res = {"protocolVersion": ver, "capabilities": {"tools": {}},
               "serverInfo": {"name": "specclaw-review", "version": "0.8.2"}}
    elif method == "ping":
        res = {}
    elif method == "tools/list":
        res = {"tools": [{"name": n, "description": d, "inputSchema": s} for n, (d, s) in TOOLS.items()]}
    elif method == "tools/call":
        p = msg.get("params") or {}
        try:
            text, err = call(p.get("name"), p.get("arguments") or {}), False
        except Exception as e:  # noqa: BLE001  a bad call must never end the server loop
            text, err = f"error: {e}", True
        res = {"content": [{"type": "text", "text": text}], "isError": err}
    else:
        return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": mid, "result": res}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            out = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        else:
            out = handle(msg)
        if out is not None:
            sys.stdout.write(json.dumps(out) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
