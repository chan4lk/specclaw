# Spec: Security rules in the presets

**Change:** 059-preset-security-rules
**Size:** bounded

## Functional Requirements

- **FR-1** `plugins/specclaw/presets/base.md` has a `## Security` section with one rule line for
  each of: secrets, input, injection, access, errors, logging, dependencies, crypto.
- **FR-2** `presets/dotnet.md`, `python.md`, `node.md`, `nextjs.md` and `react-spa.md` each have a
  `## Security` section.
- **FR-3** Each stack section holds only stack-specific rules, one short bullet each, led by a bold
  keyword. It repeats nothing already in `base.md`'s Security section.
- **FR-4** Each rule is one short line an agent can follow and a reviewer can check against code.
- **FR-5** A test fails if a preset loses its section or any of its required rules, and names the
  missing one.
- **FR-6** Each of the six `plugins/specclaw-review/review-rules/` packs has security rules with a
  severity, listed below. They repeat no rule already in the pack (B8, DN5, ND3, PY4, RS4, NX1, NX2).
- **FR-7** A test fails if a review pack loses one of those rules, and names its id.

## Required rules (keyword → what it covers)

- **base:** Secrets, Input, Injection, Access, Errors, Logging, Dependencies, Crypto. The rules name
  no stack, framework or library.
- **dotnet:** Authorization (default-deny, anonymous routes listed), Binding (DTOs never bind
  entities), Errors (one exception handler returns `ProblemDetails`), Http (`IHttpClientFactory`),
  Cors (explicit origins, never `AllowAnyOrigin` with credentials).
- **python:** Authorization (auth `Depends` on every route), Models (`extra="forbid"`), Execution (no
  `shell=True`, `eval`, `pickle` on external data), Parsing (`yaml.safe_load`), Http (`httpx` timeout,
  TLS verification on).
- **node:** Authorization (auth hook on the route group), Schemas (Zod `.strict()` on body, query,
  params), Execution (no `exec`, `eval`, `new Function`), Pollution (no merging untrusted objects),
  Cors (explicit origins), RateLimit (rate-limit auth routes).
- **nextjs:** ServerOnly (`server-only` on server modules), Cookies (`httpOnly`, `secure`,
  `sameSite`), Redirects (local paths only, never a user-supplied URL), Headers (CSP and security
  headers in `next.config`), Html (no `dangerouslySetInnerHTML` with unsanitised data).
- **react-spa:** Tokens (no tokens in `localStorage`; the server sets cookies `httpOnly` and
  `sameSite`), Redirects (login return path must be a local path), Env (no secrets in `VITE_*`), Html
  (no `dangerouslySetInnerHTML` with unsanitised data), Links (no user-supplied URLs in `href`).

## Required review rules (id → what it flags)

- **base:** B11 (no caller or ownership check), B12 (stack trace or internal detail sent to the client),
  B13 (home-made crypto, or a plain or fast digest for passwords).
- **dotnet:** DN7 (entity bound directly), DN8 (no authorization policy), DN9 (`AllowAnyOrigin` with credentials).
- **python:** PY8 (route without auth `Depends`), PY9 (`pickle`/`eval`/`exec`/`yaml.load` on external data),
  PY10 (no timeout or `verify=False`), PY11 (request model without `extra="forbid"`).
- **node:** ND6 (no auth hook), ND7 (no or non-strict schema), ND8 (`eval`, `new Function`, prototype
  pollution), ND9 (CORS wildcard with credentials), ND10 (auth route without rate limit).
- **nextjs:** NX5 (auth cookie flags), NX6 (redirect to user-supplied URL), NX7 (no CSP or security headers),
  NX8 (unsanitised `dangerouslySetInnerHTML`).
- **react-spa:** RS7 (token in web storage), RS8 (open redirect on login return), RS9 (secret in `VITE_*`),
  RS10 (user-supplied URL in `href`).

## Non-Functional Requirements

- Every preset stays within the 60-line limit (`run-preset-check-tests.sh` AC-10).
- No stack rule copies one from `base.md`; stack specifics never go into `base.md`.

## Acceptance Criteria

- [ ] **AC-1** — GIVEN `presets/base.md`, WHEN it is read, THEN it has a `## Security` section with
  a rule for secrets, input, injection, access, errors, logging, dependencies and crypto.
- [ ] **AC-2** — GIVEN the preset tests, WHEN `run-preset-check-tests.sh` runs, THEN every Security
  check passes, including AC-10 (presets ≤ 60 lines).
- [ ] **AC-3** — GIVEN `base.md` with any one of the eight rules deleted, WHEN the test runs, THEN
  it fails and names the missing rule.
- [ ] **AC-4** — GIVEN any of the five stack presets, WHEN read, THEN it has a `## Security` section
  with a rule for every keyword listed above for that stack.
- [ ] **AC-5** — GIVEN any one required rule deleted from any of the five stack presets, WHEN the
  test runs, THEN it fails and names the stack and the missing keyword. Every required rule of every
  stack is deleted in turn.
- [ ] **AC-6** — GIVEN any of the six review packs, WHEN read, THEN it has a rule for every id listed
  above for that pack.
- [ ] **AC-7** — GIVEN any one of those rules deleted from a pack, WHEN the review test runs, THEN it
  fails and names the pack and the rule id.

## Edge Cases

1. A project overrides a preset with its own `.specclaw/presets/<name>.md`: it loses these rules.
   That is the existing override contract (change 045) and is not changed here.
2. The dotnet `Errors` bullet does not repeat "no stack trace outside Development": `base.md`'s
   `Errors` rule ("Never send stack traces or internal details to the client") already requires it
   on every stack, so the stack preset keeps only the .NET-specific part (one handler returning
   `ProblemDetails`). Intentional, not a weakening.

## Approach

Add the section to each preset as plain bullets led by a bold keyword (`- **Secrets:** …`), matching
the presets' existing style, before `## Shared` in the stack presets. The test helper takes a file
and a keyword list and greps only the Security section, so a missing rule is reported by name; it
runs once for `base.md` and once per stack, each with deleted-rule mutants.

File map:
- `plugins/specclaw/presets/base.md` — add `## Security`
- `plugins/specclaw/presets/dotnet.md`, `python.md`, `node.md`, `nextjs.md`, `react-spa.md` — add `## Security`
- `plugins/specclaw/tests/run-preset-check-tests.sh` — add the Security checks
- `plugins/specclaw-review/review-rules/{base,dotnet,python,node,nextjs,react-spa}.md` — add the security rules
- `plugins/specclaw-review/tests/run-review-tests.sh` — add the pack checks
- version files (`plugins/*/.claude-plugin/plugin.json`, `plugins/*/.codex-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`) — patch bump per CLAUDE.md
