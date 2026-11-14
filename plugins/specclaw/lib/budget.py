"""specclaw budget: the context gate's rules, in one place (change 065).

Ported from ION-TBML-SUITE's dev-loop gate (.claude/hooks/dl-gate.py and
scripts/dev_loop/dashboard/gate.py at 1bdac92b9) without its dashboard, pauses or wrap-up window.
hooks/context-gate and bin/specclaw-budget both import this file, so the hook and the CLI that
change 063's dash calls cannot disagree about a role's cap. Python 3 stdlib only.
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

# Shipped context caps in tokens. A role's range is default/2 .. default*2: a launch's stated budget
# is clamped into it and `set` refuses outside it. general is any subagent no role names (decision 42).
ROLES = {"builder-backend": 200000, "builder-frontend": 200000, "code-reviewer": 150000, "general": 200000}
ROUTING = {
    "frontend": "specclaw:builder-frontend",
    "docs": "specclaw:builder-frontend",
    "default": "specclaw:builder-backend",
}
GATES = ("off", "warn", "block")
TRIP = 0.9  # the share of the cap at which the hand-off opens (TBML handoff.threshold)
TASK_LIMIT, START, CHARS_PER_TOKEN = 60000, 26000, 2.2  # TBML dev-loop-task-sizing, measured
BLOCK, LIMIT, LOG_MAX = 1 << 20, 64 << 20, 1 << 20
AGENT_ID = re.compile(r"[A-Za-z0-9_-]{1,64}")
STATED = re.compile(r"specclaw budget:(.*)")
ALLOWED = re.compile(
    r"(cd|head|tail|wc|grep|sort|cat|git(\s+-C\s+\S+)?\s+(add|commit|status|diff|log))(\s|$)|(\S*/)?specclaw-budget\s+handover(\s|$)"
)
HAND_OFF = (
    "specclaw context gate: this {role} agent is at {used}k of its {cap}k context cap. Hand off now: "
    "commit what passes its tests, run `specclaw-budget handover .specclaw <change> <task> <what is "
    "left>`, then stop and report handover. A fresh agent continues from that line."
)


# ─── config: the budget: block, read and written block-scoped (the party_val rule) ────────────

def _block(lines: list[str]) -> tuple[int | None, int]:
    """Return the column-0 `budget:` line's index and the end of its block (the next column-0 key)."""
    start = next((i for i, line in enumerate(lines) if re.match(r"budget:\s*(#.*)?$", line)), None)
    if start is None:
        return None, len(lines)
    end = start + 1
    while end < len(lines) and not re.match(r"[^\s#]", lines[end]):
        end += 1
    return start, end


def _parse(lines: list[str]) -> dict:
    """A nested map of the block's `key: value` lines by indentation; scalars stay strings."""
    root: dict = {}
    stack: list[tuple[int, dict]] = [(-1, root)]
    for raw in lines:
        text = raw.split(" #")[0].rstrip()  # shortcut: a " #" inside a quoted value is cut; no key needs one
        match = re.match(r"(\s*)([\w.-]+)\s*:(?:\s+(.*))?$", text)
        if not match:
            continue
        indent = len(match.group(1))
        while stack[-1][0] >= indent:
            stack.pop()
        key, value = match.group(2), (match.group(3) or "").strip().strip("\"'")
        parent = stack[-1][1]
        if value in ("", "{}"):
            parent[key] = {}
            stack.append((indent, parent[key]))
        else:
            parent[key] = value
    return root


def load(specclaw_dir: Path) -> dict:
    """Return {gate, roles: {role: (context, source)}, routing, warnings}. A bad value is a warning
    and its default stands: the config never stops the gate from running."""
    path = Path(specclaw_dir) / "config.yaml"
    lines = path.read_text("utf-8").splitlines() if path.is_file() else []
    start, end = _block(lines)
    raw = _parse(lines[start + 1:end]) if start is not None else {}
    warnings: list[str] = []
    gate = raw.get("gate", "warn")
    if gate not in GATES:
        warnings.append(f"budget.gate {gate!r} is not off, warn or block; running on warn")
        gate = "warn"
    roles = {name: (cap, "default") for name, cap in ROLES.items()}
    for name, fields in (raw.get("roles") if isinstance(raw.get("roles"), dict) else {}).items():
        value = fields.get("context") if isinstance(fields, dict) else None
        if name not in ROLES:
            warnings.append(f"budget.roles.{name} is not a role ({', '.join(ROLES)}); ignored")
        elif value is not None:
            if isinstance(value, str) and value.isdigit() and ROLES[name] // 2 <= int(value) <= ROLES[name] * 2:
                roles[name] = (int(value), "config")
            else:
                warnings.append(f"budget.roles.{name}.context {value!r} is outside {ROLES[name] // 2}..{ROLES[name] * 2}; using the default")
    routing = dict(ROUTING)
    for kind, agent in (raw.get("routing") if isinstance(raw.get("routing"), dict) else {}).items():
        if isinstance(agent, str) and agent:
            routing[kind] = agent
    return {"gate": gate, "roles": roles, "routing": routing, "warnings": warnings}


def roles_json(config: dict) -> dict:
    return {
        name: {"context": cap, "default": ROLES[name], "min": ROLES[name] // 2, "max": ROLES[name] * 2, "source": source}
        for name, (cap, source) in config["roles"].items()
    }


def set_context(specclaw_dir: Path, role: str, value: int) -> None:
    """Write budget.roles.<role>.context inside the budget: block; every other line is unchanged."""
    if role not in ROLES:
        raise ValueError(f"unknown role {role!r} (roles: {', '.join(ROLES)})")
    low, high = ROLES[role] // 2, ROLES[role] * 2
    if not low <= value <= high:
        raise ValueError(f"{role} context {value} is outside {low}..{high}")
    path = Path(specclaw_dir) / "config.yaml"
    if not path.is_file():
        raise ValueError(f"no config at {path}")
    lines = path.read_text("utf-8").splitlines(keepends=True)
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    start, end = _block([line.rstrip("\n") for line in lines])
    if start is None:
        lines += ["budget:\n", "  roles:\n", f"    {role}:\n", f"      context: {value}\n"]
    else:
        lines[start + 1:end] = _set_in(lines[start + 1:end], ["roles", role, "context"], str(value), 2)
    handle, tmp = tempfile.mkstemp(dir=path.parent, prefix=".config.yaml.")
    try:  # a unique temp file, the original's mode, one atomic replace; a failed write leaves nothing
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write("".join(lines))
        os.chmod(tmp, path.stat().st_mode & 0o7777)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _set_in(lines: list[str], keys: list[str], value: str, indent: int) -> list[str]:
    """Set keys[...] = value in a block's lines (children at `indent`), adding missing maps."""
    key, rest = keys[0], keys[1:]
    for i, line in enumerate(lines):
        match = re.match(rf" {{{indent}}}{re.escape(key)}\s*:(?:\s+(.*))?$", line.rstrip("\n"))
        if not match:
            continue
        if not rest:
            comment = re.search(r"\s+#.*$", line.rstrip("\n"))
            lines[i] = f"{' ' * indent}{key}: {value}{comment.group(0) if comment else ''}\n"
            return lines
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or len(lines[end]) - len(lines[end].lstrip()) > indent):
            end += 1
        while end > i + 1 and not lines[end - 1].strip():
            end -= 1  # a trailing blank line stays after the block
        comment = re.search(r"\s+#.*$", lines[i].rstrip("\n"))
        lines[i] = f"{' ' * indent}{key}:{comment.group(0) if comment else ''}\n"  # `roles: {}` becomes a map header
        lines[i + 1:end] = _set_in(lines[i + 1:end], rest, value, indent + 2)
        return lines
    tail = len(lines)
    while tail and not lines[tail - 1].strip():
        tail -= 1
    new = [f"{' ' * (indent + 2 * n)}{k}:\n" for n, k in enumerate(keys[:-1])]
    new.append(f"{' ' * (indent + 2 * len(rest))}{keys[-1]}: {value}\n")
    return lines[:tail] + new + lines[tail:]


# ─── transcripts ───────────────────────────────────────────────────────────────────────────────

def transcript_of(transcript_path: str, agent: str) -> Path:
    """A subagent's own transcript: the event's transcript_path is the session's (TBML T-b0 probe)."""
    named, own = Path(transcript_path), f"agent-{agent}.jsonl"
    return named if named.name == own else named.with_suffix("") / "subagents" / own


def _context(record: dict) -> int | None:
    if record.get("type") != "assistant":
        return None
    usage = record["message"]["usage"]
    counts = [usage.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")]
    if any(type(n) is not int or n < 0 for n in counts):
        raise TypeError("a usage count is not a whole number")
    return sum(counts)


def last_context(path: Path) -> int | None:
    """The last assistant call's context, read backwards in 1 MiB blocks up to 64 MiB; a
    half-written last line is skipped; no call yet: None. A missing file raises: a changed transcript
    layout must fail loud, not leave every subagent ungated in silence."""
    if not path.is_file():
        raise FileNotFoundError(f"no subagent transcript at {path.parent.name}/{path.name}")
    with path.open("rb") as handle:
        end = pos = handle.seek(0, os.SEEK_END)
        carry, first = b"", True
        while pos > 0 and end - pos < LIMIT:
            step = min(BLOCK, pos)
            pos -= step
            handle.seek(pos)
            lines = (handle.read(step) + carry).split(b"\n")
            if first:  # what follows the last newline is being written, or nothing
                lines.pop()
                first = False
            carry = lines.pop(0) if pos else b""
            for raw in reversed(lines):
                if b'"usage"' in raw:
                    context = _context(json.loads(raw))
                    if context is not None:
                        return context
    return None


def peak_context(path: Path) -> int | None:
    """The largest context over a transcript's assistant calls; unparsable lines are skipped."""
    peak = None
    with path.open("rb") as handle:
        for raw in handle:
            if b'"usage"' in raw:
                try:
                    context = _context(json.loads(raw))
                except (ValueError, KeyError, TypeError):
                    continue
                if context is not None:
                    peak = max(peak or 0, context)
    return peak


def first_prompt(path: Path) -> str:
    """The agent's prompt, its first record's text: only for the stated budget line."""
    with path.open("rb") as handle:
        raw = handle.readline(BLOCK)
    if not raw.endswith(b"\n"):
        return ""
    content = (json.loads(raw).get("message") or {}).get("content")
    if isinstance(content, list):
        content = next((b.get("text") for b in content if isinstance(b, dict) and b.get("type") == "text"), None)
    return content if isinstance(content, str) else ""


def find_transcript(agent: str) -> Path | None:
    root = Path(os.environ.get("SPECCLAW_TRANSCRIPTS") or Path.home() / ".claude" / "projects")
    return next(iter(root.glob(f"*/*/subagents/agent-{agent}.jsonl")), None)


# ─── the gate ──────────────────────────────────────────────────────────────────────────────────

def stated(prompt: str) -> tuple[str | None, int | None]:
    """The prompt's first line `specclaw budget: role=<role> context=<n>`, either part optional."""
    match = STATED.match(prompt.lstrip().split("\n", 1)[0])
    fields = dict(re.findall(r"(\w+)=(\S+)", match.group(1))) if match else {}
    context = fields.get("context", "")
    return fields.get("role"), int(context) if context.isdigit() else None


def role_and_cap(config: dict, agent_type: object, prompt: str) -> tuple[str, int]:
    """A known stated role, else the agent type after its last `:` when it names a role, else general;
    the cap is the stated context clamped into the role's range, else the role's context."""
    role, context = stated(prompt)
    if role not in ROLES:
        role = agent_type.rsplit(":", 1)[-1] if isinstance(agent_type, str) else ""
        role = role if role in ROLES else "general"
    default = ROLES[role]
    cap = min(max(context, default // 2), default * 2) if context is not None else config["roles"][role][0]
    return role, cap


def committing(tool: object, tool_input: object) -> bool:
    """A Bash call whose every command commits or writes the hand-off (cd and the read-only filters
    head, tail, wc, grep, sort and cat may join it). Quoted text is blanked first,
    so a commit message may hold anything. shortcut: an unquoted $(...) is not inspected; the gate is
    a quality cap on a cooperative agent, not a sandbox."""
    command = tool_input.get("command") if tool == "Bash" and isinstance(tool_input, dict) else None
    if not isinstance(command, str):
        return False
    bare = re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", "''", command)
    # Every redirect with its target (2>&1, >&2, 2>/dev/null, &>log, &>>log, > out, < in) is not a command.
    bare = re.sub(r"(\d*|&)(>>?|<)&?\s*[^\s;&|]+", " ", bare)
    parts = [part.strip() for part in re.split(r"&&|\|\||[;|&\n]", bare)]
    parts = [part for part in parts if part]
    return bool(parts) and all(ALLOWED.match(part) for part in parts)


def decide(config: dict, event: dict, prompt: str, context: int) -> tuple[str | None, str, dict]:
    """Return (None | "note" | "deny", the hand-off text, the log fields) for one subagent call."""
    role, cap = role_and_cap(config, event.get("agent_type"), prompt)
    fields = {"role": role, "context": context, "cap": cap, "gate": config["gate"]}
    if context < cap * TRIP:
        return None, "", fields
    text = HAND_OFF.format(role=role, used=context // 1000, cap=cap // 1000)
    if config["gate"] == "block" and not committing(event.get("tool_name"), event.get("tool_input")):
        return "deny", text, fields
    return "note", text, fields


def project_root(cwd: object) -> Path | None:
    """The event cwd when it holds .specclaw/config.yaml, else its git toplevel when that does."""
    if not isinstance(cwd, str) or not Path(cwd).is_dir():
        return None
    if (Path(cwd) / ".specclaw" / "config.yaml").is_file():
        return Path(cwd)
    argv = ["git", "-C", cwd, "rev-parse", "--show-toplevel"]
    out = subprocess.run(argv, capture_output=True, text=True, timeout=3, check=False).stdout.strip()
    return Path(out) if out and (Path(out) / ".specclaw" / "config.yaml").is_file() else None


def log(row: dict) -> None:
    """One line in gate.jsonl (moved to gate.1.jsonl past 1 MiB): ids and numbers, never text."""
    home = Path(os.environ.get("SPECCLAW_GATE_LOG_DIR") or Path.home() / ".claude" / "specclaw")
    home.mkdir(parents=True, exist_ok=True)
    path = home / "gate.jsonl"
    if path.exists() and path.stat().st_size > LOG_MAX:
        path.replace(home / "gate.1.jsonl")
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"at": time.time(), **row}) + "\n")


# ─── tasks and the ledger ──────────────────────────────────────────────────────────────────────

def tasks(path: Path) -> dict[str, dict]:
    """Each task's id -> {Files, Kind, Context} from a tasks.md (or a lean change.md)."""
    found: dict[str, dict] = {}
    current = None
    for line in path.read_text("utf-8").splitlines():
        head = re.match(r"\s*- \[.\] `?(T[\w.-]*?)`?(\s|$)", line)
        if head:
            current = found.setdefault(head.group(1), {})
            continue
        field = re.match(r"\s+- (Files|Kind|Context):\s*(.*)$", line)
        if current is not None and field:
            current[field.group(1)] = field.group(2).strip()
    return found


def read_tokens(root: Path, files: str) -> int:
    """START plus the existing Files' characters at CHARS_PER_TOKEN, rounded up to 1,000."""
    chars = 0
    for entry in re.split(r"[,\s]+", files.replace("`", "")):
        path = root / entry
        chars += path.stat().st_size if entry and path.is_file() else 0
    return math.ceil((START + chars / CHARS_PER_TOKEN) / 1000) * 1000


def append(specclaw_dir: Path, change: str, row: dict) -> None:
    """One line in the change's timeline.jsonl; no ev and no ts, so it is not a span (as 059's lesson)."""
    folder = Path(specclaw_dir) / "changes" / change
    if not folder.is_dir():
        raise ValueError(f"no change folder {folder}")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with (folder / "timeline.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({"kind": row.pop("kind"), "at": stamp, **row}, separators=(",", ":")) + "\n")
