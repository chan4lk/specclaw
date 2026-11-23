## Next.js rules

- **NX1** Server-only code (secrets, DB clients) imported into a `"use client"` module, or env vars without
  `NEXT_PUBLIC_` read on the client → **blocker**.
- **NX2** A Server Action or route handler without auth/ownership checks on the resource it mutates →
  **blocker**.
- **NX3** `fetch` caching/revalidation left at the default where data must be fresh (or must not be) →
  **major** with a scenario.
- **NX4** A `redirect()`/`notFound()` inside `try/catch` that swallows the thrown control-flow error →
  **major**.
- **NX5** An auth cookie set without `httpOnly`, `secure` or `sameSite` → **major**.
- **NX6** A redirect to a user-supplied URL instead of a local path → **major**.
- **NX7** No Content-Security-Policy or security headers configured in `next.config` → **minor**.
- **NX8** `dangerouslySetInnerHTML` with non-sanitised data → **blocker** (B8).
