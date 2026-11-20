# Preset: nextjs

Detected by `next` in `package.json`.

## Stack
- Next.js App Router, TypeScript strict.
- Server components by default; `"use client"` only for interactive leaves.
- Zod validates every server action and route handler input.
- Vitest for units, Playwright for screens.
- Tailwind for styling unless the project already uses something else.

## Auth guard
- `middleware.ts` guards every protected route with an explicit `matcher` list.
- Every server action and route handler re-checks the session (`requireUser()` from `lib/auth`). The middleware alone is not enough.
- Public routes are listed, never inferred.

## Layout
```
app/(public)/      unauthenticated pages
app/(app)/         guarded pages
app/api/           route handlers
components/        UI only
lib/               shared code: auth, db, schemas
```

## Rules
- Data fetching happens in server components or server actions, never in `useEffect`.
- No secrets in client components or `NEXT_PUBLIC_*`.
- One component per file.

## Security
- **ServerOnly:** import `server-only` in modules that hold secrets or DB clients.
- **Cookies:** auth cookies are `httpOnly`, `secure` and `sameSite`.
- **Redirects:** redirect only to local paths, never to a user-supplied URL.
- **Headers:** set a Content-Security-Policy and security headers in `next.config`.
- **Html:** no `dangerouslySetInnerHTML` with unsanitised data.

## Shared
- `lib/` for server code (auth, db client, schemas); `components/ui/` for shared UI primitives.

## Commands
- Test: `npx vitest run && npx playwright test`
- Lint: `npx tsc --noEmit && npx next lint`
