# Preset: node

Detected by `package.json` without `next`, `react` or `vite`.

## Stack
- TypeScript in strict mode (`"strict": true`, `"noUncheckedIndexedAccess": true`).
- ES modules (`"type": "module"`).
- Zod at every boundary: HTTP input, env vars, external responses.
- Fastify or Hono for HTTP services.
- Vitest for tests.

## Layout
```
src/
  routes/     handlers only, no logic
  services/   use cases
  adapters/   database, HTTP clients, queues
  lib/        shared code
test/
```

## Rules
- No `any`. Use `unknown` and parse with Zod.
- Env is parsed once into a typed config module.
- Dependencies are passed in (factory functions), never imported singletons.
- Errors are typed results or thrown domain errors mapped in one error handler.

## Security
- **Authorization:** an auth hook on the route group. Public routes are listed.
- **Schemas:** Zod `.strict()` on body, query and params.
- **Execution:** no `exec`, `eval` or `new Function`.
- **Pollution:** never merge untrusted objects into others; parse with Zod first.
- **Cors:** list explicit origins; rate-limit auth routes.

## Shared
- `src/lib/` (or `packages/shared/` in a monorepo): base handlers, Zod schemas reused by several routes, HTTP and retry helpers.

## Commands
- Test: `npx vitest run`
- Lint: `npx tsc --noEmit && npx eslint .`
