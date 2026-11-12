# Preset: python

Detected by `pyproject.toml` or `requirements.txt`.

## Stack
- Python 3.12, managed with `uv` (`uv add`, `uv run`).
- `ruff` for lint and format, `mypy --strict` for types.
- Pydantic models at every boundary: request bodies, config, external API responses.
- FastAPI for HTTP APIs; `httpx` for outbound HTTP.
- `pytest` for tests, in `tests/`, one file per feature.

## Layout
```
src/<package>/
  api/        routers only, no logic
  services/   use cases
  adapters/   database, HTTP clients, files
  common/     shared code
tests/
```

## Rules
- Type hints on every function signature.
- Dependencies are injected (FastAPI `Depends` or constructor arguments), never imported as globals.
- Settings come from one `pydantic-settings` class.
- Async all the way through an async route; no blocking calls inside it.

## Security
- **Authorization:** every route has an auth `Depends`. Public routes are listed.
- **Models:** request models set `extra="forbid"`.
- **Execution:** no `shell=True`, `eval` or `pickle` on external data.
- **Parsing:** `yaml.safe_load` only.
- **Http:** `httpx` calls set a timeout and keep TLS verification on (never `verify=False`).

## Shared
- `src/<package>/common/`: base adapters, shared Pydantic models, error types, retry helpers.

## Commands
- Test: `uv run pytest -q`
- Lint: `uv run ruff check . && uv run mypy src`
