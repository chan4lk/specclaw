"""Review memory: a repo-committed, bounded lesson store (findings.jsonl).

One JSON object per line. Reached only through this module (CLI and MCP server);
the plugin's PreToolUse hook denies direct reads of the file.
"""
import hashlib
import json
import math
import os
import re
import sys
import time

FILE = "findings.jsonl"
SEV_WEIGHT = {"blocker": 3, "major": 2, "minor": 1}


def fingerprint(rule, path, message):
    top = "/".join((path or "").split("/")[:2])
    words = re.findall(r"[a-z0-9_]+", (message or "").lower())[:8]
    key = "|".join([rule or "", top, " ".join(words)])
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]


def _path(mem_dir):
    return os.path.join(mem_dir, FILE)


def load(mem_dir):
    out = []
    try:
        fh = open(_path(mem_dir), encoding="utf-8")
    except OSError:
        return out
    with fh:
        for n, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                print(f"specclaw-review: WARN: memory line {n} is not JSON; skipped", file=sys.stderr)
                continue
            if isinstance(entry, dict) and entry.get("fp"):
                out.append(entry)
    return out


def save(mem_dir, entries):
    os.makedirs(mem_dir, exist_ok=True)
    tmp = _path(mem_dir) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        for e in entries:
            fh.write(json.dumps(e, sort_keys=True) + "\n")
    os.replace(tmp, _path(mem_dir))


def put(mem_dir, items, change=""):
    """Upsert findings. A repeat fingerprint bumps count/last and merges files."""
    entries = load(mem_dir)
    by_fp = {e["fp"]: e for e in entries}
    today = time.strftime("%Y-%m-%d")
    added = bumped = 0
    for it in items:
        fp = it.get("fp") or fingerprint(it.get("rule"), it.get("file"), it.get("message") or it.get("lesson"))
        files = [f for f in [it.get("file")] + list(it.get("files") or []) if f]
        if fp in by_fp:
            e = by_fp[fp]
            e["count"] = int(e.get("count", 1)) + 1
            e["last"] = today
            e["files"] = sorted(set(e.get("files", [])) | set(files))
            if SEV_WEIGHT.get(it.get("severity"), 0) > SEV_WEIGHT.get(e.get("severity"), 0):
                e["severity"] = it["severity"]
            bumped += 1
        else:
            e = {"fp": fp, "rule": it.get("rule", ""), "severity": it.get("severity", "minor"),
                 "lesson": (it.get("lesson") or it.get("message") or "").strip(), "files": sorted(set(files)),
                 "count": 1, "first": today, "last": today, "status": "active", "change": change}
            entries.append(e)
            by_fp[fp] = e
            added += 1
    save(mem_dir, entries)
    return {"added": added, "bumped": bumped, "total": len(entries)}


def _overlap(e, files):
    """3 a shared file, 2 a shared folder, 1 a shared top folder, 0 none."""
    s = 0
    for f in files:
        d = os.path.dirname(f)
        top = f.split("/")[0]
        for g in e.get("files", []):
            if g == f:
                s = max(s, 3)
            elif d and os.path.dirname(g) == d:
                s = max(s, 2)
            elif g.split("/")[0] == top:
                s = max(s, 1)
    return s


def _score(e, files):
    return _overlap(e, files) + SEV_WEIGHT.get(e.get("severity"), 0) + math.log2(max(1, int(e.get("count", 1))))


def render(e):
    lesson = e.get("lesson", "")
    if len(lesson) > 300:
        lesson = lesson[:297] + "..."
    files = ", ".join(e.get("files", [])[:3])
    return f"- [{e.get('severity')} {e.get('rule')}] {lesson} (files: {files}; seen {e.get('count', 1)}x)"


def query(mem_dir, files, budget=1500, k=10):
    """Top-k active entries for `files`, never exceeding `budget` tokens (chars/4)."""
    active = [e for e in load(mem_dir) if e.get("status") == "active"]
    ranked = sorted(active, key=lambda e: (-_score(e, files), e["fp"]))
    lines, used = [], 0
    for e in ranked[:k]:
        line = render(e)
        cost = (len(line) + 1 + 3) // 4
        if used + cost > budget:
            break
        lines.append(line)
        used += cost
    return "\n".join(lines)


def closest(mem_dir, files, k):
    """The k active entries that share a file, folder or top folder with `files`, in memory_query's order."""
    hits = [e for e in load(mem_dir) if e.get("status") == "active" and _overlap(e, files)]
    return sorted(hits, key=lambda e: (-_score(e, files), e["fp"]))[:k]


def compact(mem_dir, root, decay_days=180, max_entries=2000):
    entries = load(mem_dir)
    before = len(entries)
    cutoff = time.strftime("%Y-%m-%d", time.localtime(time.time() - decay_days * 86400))
    keep = []
    for e in entries:
        if e.get("status") == "retired":
            continue
        gone = e.get("files") and not any(os.path.exists(os.path.join(root, f)) for f in e["files"])
        if gone and e.get("last", "") < cutoff:
            continue
        keep.append(e)
    if len(keep) > max_entries:
        keep = sorted(keep, key=lambda e: (-_score(e, []), e["fp"]))[:max_entries]
    save(mem_dir, keep)
    return {"before": before, "after": len(keep)}


def mark(mem_dir, fps, status):
    entries = load(mem_dir)
    hit = 0
    for e in entries:
        if e["fp"] in fps:
            e["status"] = status
            hit += 1
    save(mem_dir, entries)
    return hit
