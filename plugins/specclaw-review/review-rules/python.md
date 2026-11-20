## Python rules

- **PY1** A mutable default argument (`def f(x=[])`, `={}`) shared across calls → **major** when it is mutated.
- **PY2** A bare `except:` or `except Exception: pass` that swallows the error turns "did not run" into
  "clear" (B3) → **major**.
- **PY3** Naive `datetime` mixed with aware values, or `datetime.now()` used where a timezone matters → **major**
  with a scenario.
- **PY4** A `subprocess` call with `shell=True` on interpolated input → **blocker** (B8).
- **PY5** A SQLAlchemy/ORM session or transaction left open on an error path, or a commit inside a loop that
  can half-apply → **major**.
- **PY6** Async code that calls blocking I/O (`requests`, `time.sleep`, sync DB drivers) inside `async def`
  → **major**.
- **PY7** Tests that `monkeypatch` the function under test, or assert on mocks only, prove nothing (B2).
- **PY8** A route with no auth `Depends` (or equivalent) that reads or changes user data → **blocker** (B13).
- **PY9** `pickle`, `eval`, `exec` or `yaml.load` on external data → **blocker** (B8).
- **PY10** `httpx`/`requests` with no timeout, or `verify=False` → **major**.
- **PY11** A Pydantic request model without `extra="forbid"` that feeds a write → **major**; otherwise **minor**.
- **PY12** A sign-in, code or token route with no rate limit → **major**.
- **PY13** A rate limit or IP check keyed on a raw `X-Forwarded-For`, or forwarded headers trusted from any source
  (`--forwarded-allow-ips '*'`) → **major**.
