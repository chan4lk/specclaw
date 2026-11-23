# Preset: base

Always applies. Listed presets add to it; `preset_overrides` in `config.yaml` may change the numbers and is recorded in `change.md`.

## Code
- No comments in code files. Names carry the meaning. Tool pragmas are allowed (`eslint-disable`, `@ts-expect-error`, `noqa`, `type: ignore`, `#pragma`, `#nullable`, shebangs).
- At most 80 lines per file, tests included (`max_lines`). Split by responsibility before you reach it.
- One responsibility per function. Keep functions under the `quality.*` complexity and length thresholds.
- No abstraction with fewer than two callers, unless the preset requires the boundary.
- No dead code, no commented-out code, no TODOs.

## Duplication
- Shared code lives in the preset's shared location (named in each preset under **Shared**).
- When the same logic appears twice, extract it there: a base class, a generic handler, a shared hook or a utility.
- `specclaw-quality-scan` measures duplication; never judge it by reading the code.

## Security
- **Secrets:** never in code, config, tests or logs. Read them from the environment or a secret store.
- **Input:** validate every external input at the boundary: type, size and an allow-list of values.
- **Injection:** no string-built SQL, shell commands, HTML, file paths or outbound URLs. Use parameters, argument arrays, output encoding, URL encoding for each path segment and query value, and paths resolved inside a fixed root.
- **Access:** every endpoint checks who the caller is and that they own the resource. Deny by default: a missing identity means deny, never "skip the check", and a role check tests the caller's role, not the target's.
- **Errors:** fail closed. Never send stack traces or internal details to the client.
- **Logging:** no secrets, tokens or personal data in logs.
- **Dependencies:** no new dependency without a reason. Commit the lockfile.
- **Crypto:** use vetted platform libraries, never home-made crypto. Store passwords with a slow, salted password hash (Argon2id, bcrypt or scrypt), never a plain digest such as MD5 or SHA-256.
- **Sessions:** logout and any password or credential change end every session of that user, not only the current one.
- **Enumeration:** sign-up, sign-in and reset answer the same (status, body, timing) whether or not the account exists, and a lookup answers the same for a missing and a forbidden resource.
- **Codes:** deliver a one-time code out-of-band, never in a response or log, and cap total failed attempts so it cannot be guessed over time.
- **DevFlags:** no flag, header or built-in value may skip or weaken authentication. Refuse to start in production when one is set.
- **Urls:** check a URL's host by parsing it and comparing the hostname, never with a substring or regex on the whole string.
- **Config:** a security control whose setting is missing refuses to start; it never falls back to off or to a permissive default.
- **Identity:** act as the caller the session or token proved, never as an identity or credential taken from a header, body field or tool argument.
- **Redirects:** redirect only to a local path or a target registered for that client, never to a URL taken from the request.

## Tests
- At most one test per acceptance criterion, named after it (`ac1_…`, `AC1 …`).
- Test behaviour through the public surface. No tests for private helpers, getters or framework wiring.

## Checks
- `specclaw-preset-check .` enforces the line limit, the comment rule and any preset structure rule.
- `specclaw-quality-scan . --gate` enforces the duplication and complexity thresholds.
