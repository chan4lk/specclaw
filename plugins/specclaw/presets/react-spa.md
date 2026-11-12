# Preset: react-spa

Detected by `react` and `vite` in `package.json` without `next`.

## Stack
- Vite, React, TypeScript strict.
- React Router for routes, TanStack Query for server state.
- Zod parses every API response.
- Vitest + Testing Library; Playwright for screens.

## Auth guard
- A `<RequireAuth>` route element wraps every protected route.
- It redirects to login and keeps the return path. The API still enforces auth; the guard is UX only.

## Layout
```
src/
  routes/       route components
  features/<x>/ components, hooks and api for one feature
  shared/       shared code
```

## Rules
- Server data only through TanStack Query hooks; no fetching in `useEffect`.
- One API client in `shared/api`, typed by Zod schemas.
- Local state stays local; no global store unless two features need it.

## Security
- **Tokens:** no tokens in `localStorage`; use `httpOnly` cookies.
- **Redirects:** the login return path must be a local path (open redirect).
- **Env:** no secrets in `VITE_*` variables; they ship to the browser.
- **Html:** no `dangerouslySetInnerHTML` with unsanitised data.
- **Links:** no user-supplied URLs in `href` (`javascript:` links).

## Shared
- `src/shared/`: the API client, shared hooks, UI primitives, schema helpers.

## Commands
- Test: `npx vitest run`
- Lint: `npx tsc --noEmit && npx eslint .`
