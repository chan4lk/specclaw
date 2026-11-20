## Node rules

- **ND1** A promise that is neither awaited nor returned (floating), or `forEach(async …)` where order or
  completion matters → **major**.
- **ND2** Errors swallowed by `.catch(() => {})` or by a `try` that returns a default (B3) → **major**.
- **ND3** `child_process.exec` with interpolated input → **blocker** (B8). Use `execFile`/`spawn` with an
  argument array instead.
- **ND4** `==` against values that may be `0`, `""` or `null` where they mean different things → **major**
  with a scenario.
- **ND5** Unbounded `JSON.parse` of external input without try/catch → **major** (B6).
- **ND6** A route or route group with no auth hook that reads or changes user data → **blocker** (B13).
- **ND7** A request body, query or params read without a schema, or a non-strict Zod schema on a write → **major**.
- **ND8** `eval`, `new Function`, or merging untrusted objects into another object (prototype pollution)
  → **blocker**.
- **ND9** CORS wildcard origin combined with credentials → **major**.
- **ND10** An auth or login route with no rate limit → **major**.
- **ND11** `trustProxy: true`, or auth rate limits keyed only on the client IP, so a spoofed `X-Forwarded-For` resets them → **major**.
