# Proposal: Security rules in the presets

**Created:** 2026-11-12
**Status:** 🟡 Draft

## Problem

The `base` preset applies to every project SpecClaw builds, but it has no security rules at all.
Only `nextjs` and `react-spa` mention security (an auth guard), and `dotnet`, `python` and `node`
say nothing. So during build, an agent gets no security guidance on most stacks, and none at all on
the real traps: over-posting in ASP.NET, `shell=True` and `pickle` in Python, prototype pollution and
`exec` in Node, open redirects and token storage on the web side.

## Proposed Solution

Two layers. `base.md` always applies first, so the general rules live there once and the stack
presets repeat none of them.

**1. `base.md` gets a `## Security` section** with short, checkable rules that hold on any stack:
secrets, input, injection, access, errors, logging, dependencies and crypto (slow salted password
hash, vetted libraries).

**2. Each stack preset gets a short `## Security` section** with only what is specific to that stack:

- **.NET:** endpoints require authorization by default and anonymous routes are listed; request DTOs
  never bind entities (over-posting); one exception handler returns `ProblemDetails`;
  `IHttpClientFactory`; explicit CORS origins, never `AllowAnyOrigin` with credentials.
- **Python:** every route has an auth `Depends`; Pydantic request models use `extra="forbid"`; no
  `shell=True`, `eval` or `pickle` on external data; `yaml.safe_load`; `httpx` with a timeout and TLS
  verification on.
- **Node:** an auth hook on the route group; Zod `.strict()` on body, query and params; no `exec`,
  `eval` or `new Function`; no merging untrusted objects (prototype pollution); explicit CORS
  origins; rate limits on auth routes.
- **Next.js:** the `server-only` package on server modules; auth cookies `httpOnly`, `secure`,
  `sameSite`; redirect only to local paths; a Content-Security-Policy and security headers in
  `next.config`; no `dangerouslySetInnerHTML` with unsanitised data.
- **React SPA:** no tokens in `localStorage` (the server sets cookies `httpOnly` and `sameSite`); the
  login return path must be a local path; no secrets in `VITE_*` variables; no
  `dangerouslySetInnerHTML` with unsanitised data and no user-supplied URLs in `href`.

Each preset stays under the 60-line limit. A test fails if a preset loses its Security rules or one
of its required rules.

## Scope

### In Scope
- A `## Security` section in `presets/base.md` and in each of the five stack presets (`nextjs` and
  `react-spa` extend their existing Auth guard section, they do not replace it).
- Tests that every one of them keeps its required rules.
- One patch version bump for the whole change.

### Out of Scope
- Review rule packs (`specclaw-review`) and the `code-reviewer` agent.
- Pen-test style checks after build, and security scanners at verify.

## Impact

- **Size:** bounded (alters six existing preset files and one test file)
- **Files affected:** 8 (estimated) plus the version files
- **Complexity:** small
- **Risk:** low
