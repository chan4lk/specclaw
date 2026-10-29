"""specclaw-review core: one library behind the CLI, the MCP server and the hook.

Rounds are an append-only ledger (changes/<c>/review/round-<n>.json); the verdict
is derived from them and HEAD on every call, never stored.
"""
import glob
import json
import os
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import review_memory as mem  # noqa: E402

PLUGIN_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_DIR = os.path.join(PLUGIN_ROOT, "review-rules")
SEVERITIES = ("blocker", "major", "minor")
SEVERITY_ALIASES = {"critical": "blocker", "high": "major", "medium": "minor", "low": "minor", "info": "minor",
                    "nit": "minor"}
# Never in a diff: records, lockfiles, generated output (+ review.skip_paths).
DEFAULT_EXCLUDE = [".specclaw/**", ".gitattributes", "*.lock", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
                   "*.generated.*", "*.gen.ts", "*.min.js", "*.map"]
# Docs: visible in a reviewed diff (code and docs must agree), but a docs-only change is `skip`
# and a finding on a doc is at most minor.
DEFAULT_DOCS = ["*.md", "docs/**"]
PASS_PROMPTS = {
    "review": "Conduct the complete, thorough review across all standards and engineering dimensions.",
    "design": ("Focus ONLY on design and implementation correctness: does this fit the architecture, respect "
               "every invariant/contract, handle real edge cases and failure modes, and is it the RIGHT design "
               "(not just code that looks correct)? Start each message with \"[design] \"."),
}
GITATTR_LINE = ".specclaw/review-memory/*.jsonl merge=union"


class ReviewError(Exception):
    def __init__(self, msg, code=2):
        super().__init__(msg)
        self.code = code


# ─── config ──────────────────────────────────────────────────────────────────

def _scalar(v):
    v = v.strip()
    if v.startswith("{") and v.endswith("}"):
        pairs = [x.split(":", 1) for x in v[1:-1].split(",") if ":" in x]
        return {k.strip(): _scalar(val) for k, val in pairs}
    if v.startswith("[") and v.endswith("]"):
        return [x.strip().strip("\"'") for x in v[1:-1].split(",") if x.strip()]
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _strip_comment(line):
    out, q = [], None
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch
        elif ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out).rstrip()


def _block_body(text, block):
    """The lines of a column-0 `block:`, the whole text when block is None, None if it is absent."""
    lines = text.splitlines()
    if block is None:
        return lines
    start = next((i for i, ln in enumerate(lines) if re.match(r"^" + re.escape(block) + r":\s*(#.*)?$", ln)), None)
    if start is None:
        return None
    body = []
    for ln in lines[start + 1:]:
        if ln.strip() and not ln[0].isspace() and not ln.lstrip().startswith("#"):
            break
        body.append(ln)
    return body


def _indented_rows(lines):
    rows = []
    for ln in lines:
        s = _strip_comment(ln)
        if s.strip():
            rows.append((len(s) - len(s.lstrip()), s.strip()))
    return rows


def _fold_row(out, key, base, ind, s):
    """Fold one parsed row into `out`; returns the key the rows after it attach to."""
    if ind == base and not s.startswith("- "):
        k, _, v = s.partition(":")
        key = k.strip()
        out[key] = _scalar(v) if v.strip() else None
    elif key is not None and s.startswith("- "):
        if not isinstance(out.get(key), list):
            out[key] = []
        out[key].append(_scalar(s[2:]))
    elif key is not None and ind > base:
        if not isinstance(out.get(key), dict):
            out[key] = {}
        k, _, v = s.partition(":")
        out[key][k.strip()] = _scalar(v)
    return key


def parse_block(text, block=None):
    """Parse a column-0 `block:` (or the top level when None) of a simple YAML file.

    Handles scalars, inline lists, `- item` lists and one nested map level. Block-scoped on
    purpose: a whole-file key search finds same-named keys in other blocks.
    """
    lines = _block_body(text, block)
    rows = _indented_rows(lines) if lines is not None else []
    if not rows:
        return {}
    base = min(r[0] for r in rows)
    out, key = {}, None
    for ind, s in rows:
        key = _fold_row(out, key, base, ind, s)
    return out


class Config:
    def __init__(self, root):
        self.root = root
        self.sc = os.path.join(root, ".specclaw")
        try:
            text = open(os.path.join(self.sc, "config.yaml"), encoding="utf-8").read()
        except OSError:
            text = ""
        self.review = parse_block(text, "review")
        self.top = parse_block(text, None)
        self.git = parse_block(text, "git")

    def get(self, key, default=None):
        v = self.review.get(key)
        return default if v in (None, "", {}) else v

    def lst(self, key):
        v = self.get(key, [])
        return v if isinstance(v, list) else [v]

    def num(self, key, default):
        try:
            return int(str(self.get(key, default)))
        except ValueError:
            return default

    def model(self, which):
        models = self.get("models", {})
        models = models if isinstance(models, dict) else {}
        return models.get(which) or {"round": "sonnet", "final": "opus"}[which]

    def path(self, key, default):
        return os.path.join(self.root, str(self.get(key, default)))

    @property
    def rules_dir(self):
        return self.path("repo_rules", ".specclaw/review/rules")

    @property
    def mem_dir(self):
        return self.path("memory_dir", ".specclaw/review-memory")


# ─── git ─────────────────────────────────────────────────────────────────────

def git(root, *args, check=True):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise ReviewError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def find_root(start="."):
    r = subprocess.run(["git", "-C", start, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if r.returncode != 0:
        raise ReviewError("not inside a git repository")
    return r.stdout.strip()


def base_ref(cfg):
    base = cfg.git.get("base_branch") or ""
    if not base:
        head = git(cfg.root, "symbolic-ref", "-q", "refs/remotes/origin/HEAD", check=False).strip()
        base = head.rsplit("/", 1)[-1] if head else "main"
    for ref in (f"origin/{base}", base):
        if git(cfg.root, "rev-parse", "-q", "--verify", ref + "^{commit}", check=False).strip():
            return ref
    raise ReviewError(f"base branch '{base}' not found (set git.base_branch)")


def head(root):
    return git(root, "rev-parse", "HEAD").strip()


# ─── paths and classification ────────────────────────────────────────────────

def _glob_re(pat):
    out, i = "", 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
            continue
        if pat.startswith("**", i):
            out += ".*"
            i += 2
            continue
        out += "[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c)
        i += 1
    return re.compile("^" + out + "$")


def glob_match(path, pat):
    if _glob_re(pat).match(path):
        return True
    return "/" not in pat and bool(_glob_re(pat).match(path.rsplit("/", 1)[-1]))


def _forced(cfg, path):
    return any(glob_match(path, p) for p in cfg.lst("review_paths"))


def is_excluded(cfg, path):
    return not _forced(cfg, path) and any(glob_match(path, p) for p in DEFAULT_EXCLUDE + cfg.lst("skip_paths"))


def is_doc(cfg, path):
    return not _forced(cfg, path) and any(glob_match(path, p) for p in DEFAULT_DOCS)


def is_skip(cfg, path):
    """Excluded or a doc: never decides that a change needs review, never above minor."""
    return is_excluded(cfg, path) or is_doc(cfg, path)


def resolve_since(cfg, since):
    """`since` names a commit; resolve it to a sha so it can never reach git as an option."""
    if not since:
        return None
    if since.startswith("-"):
        raise ReviewError(f"--since must name a commit, not an option: {since!r}")
    sha = git(cfg.root, "rev-parse", "--verify", "--quiet", "--end-of-options", f"{since}^{{commit}}", check=False).strip()
    if not re.fullmatch(r"[0-9a-f]{40,64}", sha):
        raise ReviewError(f"--since is not a commit: {since!r}")
    return sha


def changed_files(cfg, since=None):
    since = resolve_since(cfg, since)
    if since:
        out = git(cfg.root, "log", "--no-merges", "--first-parent", "--name-only", "--format=", f"{since}..HEAD")
    else:
        mb = git(cfg.root, "merge-base", base_ref(cfg), "HEAD").strip()
        out = git(cfg.root, "diff", "--name-only", f"{mb}..HEAD")
    return sorted({f for f in out.splitlines() if f.strip()})


def classify(cfg, since=None):
    files = changed_files(cfg, since)
    code = [f for f in files if not is_skip(cfg, f)]
    diffable = [f for f in files if not is_excluded(cfg, f)] if code else []
    risky = [f for f in code if any(glob_match(f, p) for p in cfg.lst("risky_paths"))]
    return {"tier": "review" if code else "skip", "files": diffable, "code": code,
            "skipped": [f for f in files if f not in diffable], "risky": risky}


def diff_text(cfg, files, since=None):
    if not files:
        return ""
    since = resolve_since(cfg, since)
    if since:
        return git(cfg.root, "log", "-p", "--no-merges", "--first-parent", "--format=commit %h %s",
                   f"{since}..HEAD", "--", *files)
    mb = git(cfg.root, "merge-base", base_ref(cfg), "HEAD").strip()
    return git(cfg.root, "diff", f"{mb}..HEAD", "--", *files)


# ─── impact set ──────────────────────────────────────────────────────────────

SYMBOL_RES = [re.compile(p) for p in (
    r"\bdef\s+([A-Za-z_]\w{3,})", r"\bclass\s+([A-Za-z_]\w{3,})", r"\bfunction\s+([A-Za-z_]\w{3,})",
    r"\b(?:const|let|var)\s+([A-Za-z_]\w{3,})\s*=", r"\b(?:func|fn)\s+([A-Za-z_]\w{3,})",
    r"\b(?:public|private|internal|protected)\s[^=;(]*?\b([A-Za-z_]\w{3,})\s*\(")]


def changed_symbols(diff):
    names = []
    for ln in diff.splitlines():
        if ln.startswith(("+++", "---")):
            continue
        if ln.startswith(("+", "-", "@@", " ")):
            for rx in SYMBOL_RES:
                for m in rx.findall(ln):
                    if m not in names:
                        names.append(m)
    return names


def impact_set(cfg, diff, changed):
    cap = cfg.num("impact_cap", 20)
    hits = {}
    for name in changed_symbols(diff)[:40]:
        out = git(cfg.root, "grep", "-n", "-w", "-I", "-F", "-e", name, check=False)
        for ln in out.splitlines():
            path = ln.split(":", 1)[0]
            if path in changed or is_skip(cfg, path):
                continue
            if path not in hits and len(hits) >= cap:
                continue
            bucket = hits.setdefault(path, [])
            if len(bucket) < 3:
                bucket.append(ln[:200])
    return hits


# ─── rules ───────────────────────────────────────────────────────────────────

def ensure(cfg):
    """Lazy, idempotent init: repo rules dir, memory dir, .gitattributes union merge."""
    os.makedirs(cfg.rules_dir, exist_ok=True)
    readme = os.path.join(cfg.rules_dir, "README.md")
    if not os.path.exists(readme):
        with open(readme, "w", encoding="utf-8") as fh:
            fh.write("# Repo review rules\n\nEvery other `*.md` here is appended to the review rulebook, in name "
                     "order, after the plugin packs. Give each rule a stable ID (`R1`, `R2`…).\n"
                     "`specclaw-review rules` prints the resolved rulebook.\n")
    os.makedirs(cfg.mem_dir, exist_ok=True)
    ga = os.path.join(cfg.root, ".gitattributes")
    try:
        existing = open(ga, encoding="utf-8").read()
    except OSError:
        existing = ""
    if GITATTR_LINE not in existing.splitlines():
        with open(ga, "a", encoding="utf-8") as fh:
            if existing and not existing.endswith("\n"):
                fh.write("\n")
            fh.write(GITATTR_LINE + "\n")


def pack_names(cfg):
    names = cfg.lst("rules") or [p for p in (cfg.top.get("presets") or []) if isinstance(p, str)]
    return ["base"] + [n for n in names if n != "base"]


def governance_files(cfg):
    """Tracked files matching review.governance, in pattern order; read live every round."""
    pats = cfg.lst("governance")
    if not pats:
        return []
    tracked = git(cfg.root, "ls-files").splitlines()
    out = []
    for pat in pats:
        for f in sorted(t for t in tracked if glob_match(t, pat)):
            if f not in out:
                out.append(f)
    return out


def rulebook(cfg):
    parts, notes = [], []
    for name in pack_names(cfg):
        path = os.path.join(PACK_DIR, f"{name}.md")
        if os.path.exists(path):
            parts.append(open(path, encoding="utf-8").read().strip())
        else:
            notes.append(f"note: no review pack named '{name}' — skipped")
    for path in sorted(glob.glob(os.path.join(glob.escape(cfg.rules_dir), "*.md"))):
        if os.path.basename(path) == "README.md":
            continue
        parts.append(open(path, encoding="utf-8").read().strip())
    for path in governance_files(cfg):
        body = open(os.path.join(cfg.root, path), encoding="utf-8", errors="replace").read().strip()
        parts.append(f"## Project governance: {path}\n\n{body}")
    overrides = cfg.get("rule_overrides", {})
    if isinstance(overrides, dict) and overrides:
        parts.append("## Severity overrides\n\n" + "\n".join(f"- {k}: at most {v}" for k, v in sorted(overrides.items())))
    return "\n\n".join(parts), notes


# ─── rounds ──────────────────────────────────────────────────────────────────

def change_dir(cfg, change):
    if not change or "/" in change or change in (".", ".."):
        raise ReviewError("--change must name a change folder")
    for d in (os.path.join(cfg.sc, "changes", change), os.path.join(cfg.sc, "changes", "archive", change)):
        if os.path.isdir(d):
            return d
    raise ReviewError(f"no change folder .specclaw/changes/{change}")


def rounds(cdir):
    out = []
    for p in glob.glob(os.path.join(glob.escape(cdir), "review", "round-*.json")):
        m = re.search(r"round-(\d+)\.json$", p)
        if not m:
            continue
        try:
            out.append((int(m.group(1)), json.load(open(p, encoding="utf-8"))))
        except (ValueError, OSError):
            continue
    return [r for _, r in sorted(out, key=lambda x: x[0])]


OUTPUT_CONTRACT = """Return ONLY a JSON array, no prose. One object per finding:
[{"severity":"blocker|major|minor","rule":"<rule id, e.g. B1>","file":"<path>","line":<int>,
  "message":"<the defect and the fix>","scenario":"<concrete input -> wrong result; REQUIRED for blocker/major>",
  "in_delta":<true if the defect is in lines this diff adds or changes, else false>}]
Return [] when there is nothing to report. A blocker/major without a concrete scenario will be downgraded."""
PROJECT_CONTRACT = OUTPUT_CONTRACT.replace("REQUIRED for blocker/major", "when you can give one").replace(
    " A blocker/major without a concrete scenario will be downgraded.", "")
PLUGIN_SEVERITY = ("Severity: blocker = data loss/security/law break; major = wrong behaviour a test could show; "
                   "minor = everything else. Records, process docs and lint are never major.")
PROJECT_SEVERITY = ("Severity: the project's governance below decides it; where it is silent, blocker = data loss/"
                    "security/law break, major = wrong behaviour, minor = what can safely wait. The rule packs' "
                    "severity hints yield to the project's.")


def project_severity(cfg):
    """review.severity: project lets the repo's governance set severity (and drops the scenario gate)."""
    default = "project" if cfg.lst("governance") else "plugin"   # a repo with its own law sets its own severity
    return str(cfg.get("severity", default)) == "project"


def build_system(cfg, cls):
    """The rulebook and memory slice: identical across a round's passes (cacheable)."""
    book, _ = rulebook(cfg)
    memory = mem.query(cfg.mem_dir, cls["files"], cfg.num("memory_budget", 1500), cfg.num("memory_k", 10))
    parts = [
        "You are a strict code reviewer. Review ONLY the diff you are given against the rulebook. No praise, no "
        "features, no refactors outside the diff. " + (PROJECT_SEVERITY if project_severity(cfg) else PLUGIN_SEVERITY) +
        " Docs in the diff are there so code and docs can be checked against each other.",
        "# Rulebook\n\n" + book,
    ]
    if memory:
        parts.append("# Lessons this repo already learned for these files\n\n" + memory)
    return "\n\n".join(parts)


def build_prompt(cfg, diff, impact, prior, final, focus):
    parts = [focus]
    if cfg.get("tools"):
        parts.append("You may Read/Grep source and design docs for context; do not re-read the rulebook files.")
    if prior:
        lines = "\n".join(f"- [{f['severity']} {f.get('rule','')}] {f.get('file')}:{f.get('line')} {f.get('message')}"
                          for f in prior)
        parts.append("# Findings from the previous round (now claimed fixed)\n\n" + lines +
                     "\n\nFor each: is the fix a CLASS fix (every variant, caller and second copy) or an INSTANCE "
                     "fix (only the named case)? An instance fix is a finding.")
    if impact:
        lines = "\n".join(ln for hits in impact.values() for ln in hits)
        parts.append("# Impact set (other files that reference symbols this diff changes)\n\n" + lines)
    scope = "the WHOLE change (final pass)" if final else "this round's changes"
    cap = cfg.num("max_diff_lines", 6000)
    dl = diff.splitlines()
    if len(dl) > cap:
        diff = "\n".join(dl[:cap]) + f"\n[... diff truncated at {cap} lines ...]"
    parts.append(f"# Diff: {scope}\n\n```diff\n{diff}\n```")
    parts.append(PROJECT_CONTRACT if project_severity(cfg) else OUTPUT_CONTRACT)
    return "\n\n".join(parts)


def backend_argv(cfg, model, system_file):
    """argv for one pass, and whether the system prompt still has to go on stdin."""
    tools = str(cfg.get("tools", "") or "")
    turns = str(cfg.num("max_turns", 12 if tools else 1))
    tmpl = cfg.get("backend")
    if tmpl:
        subs = {"{model}": model, "{tools}": tools, "{max_turns}": turns, "{system_file}": system_file}
        argv = []
        for a in shlex.split(str(tmpl)):
            for k, v in subs.items():
                a = a.replace(k, v)
            argv.append(a)
        return argv, "{system_file}" not in str(tmpl)
    argv = ["claude", "-p", "--model", model, "--append-system-prompt-file", system_file,
            "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
            "--permission-mode", "dontAsk", "--output-format", "text", "--max-turns", turns]
    if tools:
        argv += ["--tools", tools, "--allowedTools", tools, "--disallowedTools", "Read(~/.claude/**)"]
    else:
        argv += ["--tools", ""]
    return argv, False


def call_backend(cfg, model, system, prompt):
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as fh:
        fh.write(system)
        sysfile = fh.name
    argv, inline = backend_argv(cfg, model, sysfile)
    if inline:
        prompt = system + "\n\n" + prompt
    try:
        r = subprocess.run(argv, input=prompt, capture_output=True, text=True, cwd=cfg.root,
                           timeout=cfg.num("timeout_seconds", 900))
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ReviewError(f"backend did not run: {e}", 3)
    finally:
        os.unlink(sysfile)
    if r.returncode != 0:
        raise ReviewError(f"backend exited {r.returncode}: {(r.stderr or r.stdout).strip()[-400:]}", 3)
    return r.stdout


def parse_findings(text):
    text = text.strip()
    dec = json.JSONDecoder()
    for i, ch in enumerate(text):
        if ch != "[":
            continue
        try:
            val, _ = dec.raw_decode(text[i:])
        except ValueError:
            continue
        if isinstance(val, list) and all(isinstance(x, dict) for x in val):
            out = []
            for x in val:   # fail closed: an odd severity or a missing file never drops a finding
                sev = str(x.get("severity", "")).lower()
                x["severity"] = sev if sev in SEVERITIES else SEVERITY_ALIASES.get(sev, "major")
                x["file"] = str(x.get("file") or "(unspecified)")
                out.append(x)
            return out
    raise ReviewError("backend output holds no JSON array of findings", 3)


def _symbols(f):
    """Backticked identifiers in a message: two passes naming the same symbol in one file are one finding."""
    return {t for t in re.findall(r"`([A-Za-z_][\w.]{2,})", f.get("message") or "")}


def calibrate(cfg, findings):
    out = []
    for f in findings:
        f["original_severity"] = f["severity"]
        if f["severity"] in ("blocker", "major") and not project_severity(cfg) and not str(f.get("scenario") or "").strip():
            f["severity"] = "minor"
            f["calibrated"] = "no scenario"
        if f["severity"] != "minor" and is_skip(cfg, f["file"]):
            f["severity"] = "minor"
            f["calibrated"] = "records/docs/generated"
        try:
            f["line"] = int(f.get("line") or 0)
        except (TypeError, ValueError):
            f["line"] = 0
        f["pre_existing"] = f.get("in_delta") is False and f["severity"] != "blocker"
        f["fp"] = mem.fingerprint(f.get("rule"), f["file"], f.get("message"))
        dup = next((g for g in out if g["file"] == f["file"] and (
            (abs(g["line"] - f["line"]) <= 3 and (g.get("rule") == f.get("rule") or g.get("pass") != f.get("pass")))
            or (g.get("pass") != f.get("pass") and _symbols(g) & _symbols(f)))), None)
        if dup:
            if SEVERITIES.index(f["severity"]) < SEVERITIES.index(dup["severity"]):
                out[out.index(dup)] = f
            continue
        out.append(f)
    return out


def counts(findings):
    c = {s: 0 for s in SEVERITIES}
    for f in findings:
        if not f.get("pre_existing"):
            c[f["severity"]] += 1
    return c


def blocking(findings):
    return [f for f in findings if f["severity"] in ("blocker", "major") and not f.get("pre_existing")]


def append_follow_ups(cdir, findings, round_no):
    path = os.path.join(cdir, "follow-ups.md")
    existing = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    new = [f for f in findings if (f["severity"] == "minor" or f.get("pre_existing")) and f"fp:{f['fp']}" not in existing]
    if not new:
        return 0
    with open(path, "a", encoding="utf-8") as fh:
        if not existing:
            fh.write("# Follow-ups\n\nDeferred by the review loop: minors and pre-existing findings.\n\n")
        for f in new:
            fh.write(f"- [{f['severity']} {f.get('rule','')}] `{f['file']}:{f['line']}` {f.get('message','')} "
                     f"(round {round_no}) <!-- fp:{f['fp']} -->\n")
    return len(new)


def _run_passes(cfg, cls, rec, diff, model, prev, final):
    """Run every configured review pass over the diff; records the prompt sizes on `rec`."""
    impact = impact_set(cfg, diff, set(cls["files"]))
    prior = blocking(prev[-1]["findings"]) if prev and not final else []
    passes = cfg.lst("passes") or ["review"]
    unknown = [p for p in passes if p not in PASS_PROMPTS]
    if unknown:
        raise ReviewError(f"unknown review pass(es): {', '.join(unknown)} (known: {', '.join(PASS_PROMPTS)})")
    system = build_system(cfg, cls)
    rec.update(passes=passes, tools=str(cfg.get("tools", "") or ""), system_chars=len(system),
               impact=sorted(impact))
    raw = []
    for name in passes:
        prompt = build_prompt(cfg, diff, impact, prior, final, PASS_PROMPTS[name])
        for f in parse_findings(call_backend(cfg, model, system, prompt)):
            f["pass"] = name
            raw.append(f)
    rec["prompt_chars"] = len(system) + len(prompt)
    return raw


def _settle_round(cfg, cdir, change, rec, found, prev, n):
    """Judge the calibrated findings: status, escalation, lesson memory and follow-ups."""
    rec["findings"] = found
    block = blocking(found)
    seen = {}
    for r in prev:
        for f in blocking(r.get("findings", [])):
            seen.setdefault((f.get("rule"), f["file"]), set()).add(r["round"])
    repeat = [f for f in block if len(seen.get((f.get("rule"), f["file"]), ())) >= 2]
    rec["status"] = "escalate" if repeat else "open" if block else "clean"
    rec["escalated"] = [f["fp"] for f in repeat]
    # a lesson counts once per change: a finding still open next round is not a recurrence
    known = {g.get("fp") for r in prev for g in r.get("findings", [])}
    mem.put(cfg.mem_dir, [dict(f, lesson=f.get("message")) for f in block if f["fp"] not in known], change)
    append_follow_ups(cdir, found, n)


def run_round(cfg, change, since=None, final=False):
    cdir = change_dir(cfg, change)
    ensure(cfg)
    prev = rounds(cdir)
    n = len(prev) + 1
    if final:
        since = None
    cls = classify(cfg, since)
    model = cfg.model("final" if final or cls["risky"] else "round")
    rec = {"round": n, "final": final, "since": since, "head": head(cfg.root), "model": model,
           "tier": cls["tier"], "files": cls["files"], "ts_start": int(time.time()), "findings": []}
    try:
        if cls["tier"] == "skip":
            rec["status"] = "skipped"
        else:
            diff = diff_text(cfg, cls["files"], since)
            if not diff.strip():
                raise ReviewError("empty diff for a non-skip change", 3)
            raw = _run_passes(cfg, cls, rec, diff, model, prev, final)
            _settle_round(cfg, cdir, change, rec, calibrate(cfg, raw), prev, n)
    except ReviewError as e:
        if e.code != 3:
            raise
        rec["status"] = "not_run"
        rec["error"] = str(e)
    rec["counts"] = counts(rec["findings"])
    rec["ts_end"] = int(time.time())
    os.makedirs(os.path.join(cdir, "review"), exist_ok=True)
    with open(os.path.join(cdir, "review", f"round-{n}.json"), "w", encoding="utf-8") as fh:
        json.dump(rec, fh, indent=1, sort_keys=True)
    return rec


EXIT_BY_STATUS = {"clean": 0, "skipped": 0, "open": 1, "not_run": 3, "escalate": 4}


# ─── verdict ─────────────────────────────────────────────────────────────────

def _final_pass_drift(cfg, fsha):
    """(still_ok, note) for a final pass that is not HEAD: only records-only commits may follow it."""
    reachable = subprocess.run(["git", "-C", cfg.root, "merge-base", "--is-ancestor", fsha, "HEAD"],
                               capture_output=True).returncode == 0
    if not reachable:
        return False, " (the final pass is not in HEAD's history: rebased or shallow; run --final again)"
    later = [f for f in git(cfg.root, "diff", "--name-only", f"{fsha}..HEAD").splitlines() if f.strip()]
    if any(not is_skip(cfg, f) for f in later):
        return False, " (code changed after the final pass)"
    return True, " (+ records-only commits)"


def verdict(cfg, change):
    cdir = change_dir(cfg, change)
    rs = rounds(cdir)
    now = head(cfg.root)
    rm, fm = cfg.model("round"), cfg.model("final")
    if not rs:
        return 1, f"Review: NOT_RUN — 0 rounds, final pass missing, models {rm}/{fm}"
    last = rs[-1]
    finals = [r for r in rs if r.get("final") and r.get("status") in ("clean", "skipped")]
    fsha = finals[-1]["head"] if finals else None
    state = {"clean": "CLEAN", "skipped": "CLEAN", "open": "OPEN", "escalate": "ESCALATE", "not_run": "NOT_RUN"}[last["status"]]
    ok = state == "CLEAN" and fsha is not None and last.get("final")
    note = ""
    if ok and fsha != now:
        ok, note = _final_pass_drift(cfg, fsha)
    if state == "CLEAN" and not ok and not note:
        note = " (final pass missing)"
    final_txt = fsha[:10] if fsha else "missing"
    c = last.get("counts", {})
    line = (f"Review: {state}{note} — {len(rs)} rounds, final pass {final_txt}, models {rm}/{fm}; "
            f"last round {c.get('blocker',0)}/{c.get('major',0)}/{c.get('minor',0)} b/M/m")
    return (0 if ok else 1), line


# ─── stats ───────────────────────────────────────────────────────────────────

def stats(cfg):
    dirs = glob.glob(os.path.join(glob.escape(cfg.sc), "changes", "*")) + glob.glob(os.path.join(glob.escape(cfg.sc), "changes", "archive", "*"))
    per_change, by_model, to_clean, model_secs = [], {}, [], []
    for d in sorted(dirs):
        rs = rounds(d)
        if not rs:
            continue
        name = os.path.basename(d)
        bm = [r.get("counts", {}).get("blocker", 0) + r.get("counts", {}).get("major", 0) for r in rs]
        per_change.append(f"{name}: {len(rs)} rounds, b+M per round {bm}")
        for r in rs:
            agg = by_model.setdefault(r.get("model", "?"), [0, 0])
            agg[0] += 1
            agg[1] += r.get("counts", {}).get("blocker", 0) + r.get("counts", {}).get("major", 0)
            model_secs.append(r.get("ts_end", 0) - r.get("ts_start", 0))
        clean = next((r for r in rs if r.get("status") in ("clean", "skipped")), None)
        if clean:
            to_clean.append(clean["ts_end"] - rs[0]["ts_start"])
    if not per_change:
        return "no review rounds recorded yet"
    lens = [int(s.split(": ")[1].split()[0]) for s in per_change]
    lines = per_change + ["", f"median rounds: {statistics.median(lens)}"]
    if to_clean:
        lines.append(f"median time to first clean round: {int(statistics.median(to_clean) // 60)} min")
    lines.append(f"median model time per round: {int(statistics.median(model_secs))} s")
    for m, (n, bm) in sorted(by_model.items()):
        lines.append(f"model {m}: {n} rounds, {bm / n:.2f} b+M per round")
    return "\n".join(lines)


# ─── learn ───────────────────────────────────────────────────────────────────

def learn_candidates(cfg):
    return [e for e in mem.load(cfg.mem_dir) if e.get("status") == "active" and int(e.get("count", 1)) >= 2]


def learn_propose(cfg):
    cands = learn_candidates(cfg)
    if not cands:
        return "no recurring lessons (count >= 2) to propose"
    out = [f"{len(cands)} proposed rule(s) for {os.path.relpath(cfg.rules_dir, cfg.root)}/learned.md "
           "(dry-run; apply with `learn --apply <fp>...` after a human approves):", ""]
    for e in cands:
        out.append(f"- fp {e['fp']} [{e['severity']} {e.get('rule','')}] seen {e['count']}x in "
                   f"{', '.join(e.get('files', [])[:3])}: {e.get('lesson','')}")
    return "\n".join(out)


def learn_apply(cfg, fps):
    ensure(cfg)
    cands = {e["fp"]: e for e in learn_candidates(cfg)}
    picked = [cands[f] for f in fps if f in cands]
    if not picked:
        raise ReviewError("none of the given fingerprints is a current learn candidate")
    path = os.path.join(cfg.rules_dir, "learned.md")
    text = open(path, encoding="utf-8").read() if os.path.exists(path) else "# Learned rules\n\nPromoted from review memory by `specclaw-review learn`.\n\n"
    n = max([int(x) for x in re.findall(r"\*\*L(\d+)\*\*", text)] or [0])
    for e in picked:
        n += 1
        text += (f"- **L{n}** ({e['severity']}; from {e.get('rule','')}, seen {e['count']}x in "
                 f"{', '.join(e.get('files', [])[:3])}): {e.get('lesson','')}\n")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    mem.mark(cfg.mem_dir, {e["fp"] for e in picked}, "ruled")
    return f"wrote {len(picked)} rule(s) to {os.path.relpath(path, cfg.root)}"


def learn_import(cfg, paths, apply=False):
    plan = []
    for p in paths:
        src = os.path.abspath(p)
        if not os.path.isfile(src):
            raise ReviewError(f"not a file: {p}")
        stem = re.sub(r"[^A-Za-z0-9_.-]", "-", os.path.splitext(os.path.basename(src))[0])
        plan.append((src, os.path.join(cfg.rules_dir, f"imported-{stem}.md")))
    if not apply:
        return "dry-run; re-run with --apply to write:\n" + "\n".join(f"  {s} -> {os.path.relpath(d, cfg.root)}" for s, d in plan)
    ensure(cfg)
    for src, dst in plan:
        body = open(src, encoding="utf-8", errors="replace").read()
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(f"<!-- imported by specclaw-review from {os.path.relpath(src, cfg.root)} on "
                     f"{time.strftime('%Y-%m-%d')} -->\n\n{body}")
    return f"imported {len(plan)} file(s) into {os.path.relpath(cfg.rules_dir, cfg.root)}"


def install_claude_rule(cfg):
    src = os.path.join(PLUGIN_ROOT, "templates", "claude-rule.md")
    dst = os.path.join(cfg.root, ".claude", "rules", "specclaw-review-memory.md")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, encoding="utf-8") as fh, open(dst, "w", encoding="utf-8") as out:
        out.write(fh.read())
    return os.path.relpath(dst, cfg.root)


# ─── discover ────────────────────────────────────────────────────────────────

DISCOVER = [  # (category, patterns) matched case-insensitively against tracked paths
    ("agent instructions", ["CLAUDE.md", "**/CLAUDE.md", "AGENTS.md", "**/AGENTS.md", "GEMINI.md",
                            ".github/copilot-instructions.md", ".cursorrules", ".cursor/rules/**"]),
    ("conventions", [".specclaw/context.md", "CONTRIBUTING.md", "**/*convention*.md", "**/*style*guide*.md", "**/*guideline*.md",
                     "**/*coding-standard*.md"]),
    ("review standards", ["**/*pitfall*", "**/*review*standard*", "**/*review*prompt*", "**/*review*checklist*",
                          ".github/pull_request_template.md", "**/code-reviewer.md"]),
    ("decisions (read with tools, not inlined)", ["docs/adr/**", "**/adr/**", "**/decisions/**"]),
]
DISCOVER_SKIP = ["node_modules/**", "**/node_modules/**", "vendor/**", "**/vendor/**", ".specclaw/changes/**",
                 "**/fixtures/**", "**/testdata/**", "**/templates/**", "**/__snapshots__/**", "**/dist/**", "**/build/**",
                 ".claude/skills/**", ".agents/skills/**", "**/.claude/skills/**"]
DOC_EXT = (".md", ".mdc", ".txt", ".cursorrules")
SEVERITY_RE = re.compile(r"\b(blocker|major|minor|severity)\b", re.I)


def _pr_host(cfg):
    remotes = git(cfg.root, "remote", "-v", check=False)
    if "github.com" in remotes:
        r = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True) if shutil.which("gh") else None
        return "github (gh authenticated)" if r is not None and r.returncode == 0 else "github (gh not authenticated)"
    azdo = parse_block(open(os.path.join(cfg.sc, "config.yaml"), encoding="utf-8").read(), "azdo") \
        if os.path.exists(os.path.join(cfg.sc, "config.yaml")) else {}
    if "dev.azure.com" in remotes or str(azdo.get("enabled")) == "true":
        env = os.path.join(cfg.sc, ".env")
        has = os.path.exists(env) and any(ln.startswith("AZDO_TOKEN=") and len(ln.strip()) > 11
                                          for ln in open(env, encoding="utf-8", errors="replace"))
        return "azure devops (token in .specclaw/.env)" if has else "azure devops (no token: run auth-azdo)"
    return "none detected"


def _scan_governance(cfg):
    """Tracked docs that look like review governance, one record per file, first category wins."""
    tracked = git(cfg.root, "ls-files").splitlines()
    tracked = [t for t in tracked if t.lower().endswith(DOC_EXT) and not any(glob_match(t.lower(), p) for p in DISCOVER_SKIP)]
    seen, found = set(), []
    for cat, pats in DISCOVER:
        for t in sorted(tracked):
            if t in seen or not any(glob_match(t.lower(), p.lower()) for p in pats):
                continue
            seen.add(t)
            try:
                text = open(os.path.join(cfg.root, t), encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            found.append({"category": cat, "path": t, "lines": text.count("\n") + 1, "chars": len(text),
                          "defines_severity": bool(SEVERITY_RE.search(text))})
    return found


def discover(cfg):
    """Read-only scan for the repo's own review governance; suggests config, writes nothing."""
    found = _scan_governance(cfg)
    inline = [f for f in found if not f["category"].startswith("decisions")]
    budget = cfg.num("governance_budget", 200000)
    total = sum(f["chars"] for f in inline)
    changes = glob.glob(os.path.join(glob.escape(cfg.sc), "changes", "**", "*.md"), recursive=True)
    return {
        "governance": found,
        "inline_chars": total,
        "over_budget": total > budget,
        "budget": budget,
        "defines_severity": any(f["defines_severity"] for f in inline),
        "repo_rules": sorted(os.path.basename(p) for p in glob.glob(os.path.join(glob.escape(cfg.rules_dir), "*.md"))
                             if os.path.basename(p) != "README.md"),
        "learnings_files": len([p for p in changes if p.endswith("learnings.md")])
        + os.path.exists(os.path.join(cfg.sc, "learnings.md")),
        "follow_ups_files": len([p for p in changes if p.endswith("follow-ups.md")]),
        "learn_candidates": len(learn_candidates(cfg)),
        "presets": pack_names(cfg)[1:],
        "pr_host": _pr_host(cfg),
        "suggested_config": suggested_config(cfg, inline),
    }


def suggested_config(cfg, inline):
    lines = ["review:", f"  rules: [{', '.join(pack_names(cfg)[1:])}]", "  passes: [review, design]",
             '  tools: "Read,Grep,Glob"', "  max_turns: 12"]
    if inline:
        lines.append("  governance:")
        lines += [f'    - "{f["path"]}"' for f in inline]
    return "\n".join(lines)


def discover_text(d):
    out = ["# specclaw-review discover (read-only; nothing written)", ""]
    if not d["governance"]:
        out.append("No governance files found: the plugin packs alone will apply. The `rules` skill can draft repo rules.")
    cat = None
    for f in d["governance"]:
        if f["category"] != cat:
            cat = f["category"]
            out.append(f"\n## {cat}")
        sev = "  [defines severity]" if f["defines_severity"] else ""
        out.append(f"- {f['path']}  ({f['lines']} lines, {f['chars']} chars){sev}")
    out.append(f"\nInlined rulebook if adopted: {d['inline_chars']} chars"
               + (f"  WARNING: over the {d['budget']}-char budget; trim or move docs to read-with-tools." if d["over_budget"] else ""))
    if d["defines_severity"]:
        out.append("Severity: these files define it, so `severity: project` (the default with governance) applies.")
    out.append(f"Repo rules today: {', '.join(d['repo_rules']) or 'none'}")
    out.append(f"Review history on disk: {d['learnings_files']} learnings.md, {d['follow_ups_files']} follow-ups.md, "
               f"{d['learn_candidates']} recurring memory lessons")
    out.append(f"PR host: {d['pr_host']}")
    out.append("\n## Suggested config\n\n" + d["suggested_config"])
    return "\n".join(out)
