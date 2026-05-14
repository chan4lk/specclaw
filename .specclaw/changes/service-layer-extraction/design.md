# Design: Service Layer Extraction

**Change:** service-layer-extraction
**Created:** 2026-05-09

## Architecture

Introduce `src/lib/services/` as a pure business-logic layer. Files in this layer:
- Import Prisma and lib utilities (`rbac`, `scoring`)
- Have **no** dependency on Next.js, `next-auth`, MCP SDK, or HTTP
- Are called by both REST route handlers and MCP tool handlers

```
src/lib/services/
  key-results.ts   — score recalc + KR authorization guards
  cycles.ts        — cycle activation helper
  users.ts         — canonical user list query
```

## File-by-file design

---

### `src/lib/services/key-results.ts`

```ts
// Recalculate and persist objective score from all its KRs
export async function recalculateObjectiveScore(
  objectiveId: string,
  prisma: PrismaClient,
): Promise<void>

// Throw McpError (for MCP) or return false (let callers handle) — pick: throw ServiceError
export function assertCanEditKr(
  kr: { ownerId: string },
  ctx: { userId: string | null; role: string | null },
): void   // throws ServiceForbiddenError if denied

export function assertCanDeleteKr(
  kr: { ownerId: string },
  ctx: { userId: string | null; role: string | null },
): void   // throws ServiceForbiddenError if denied
```

**`ServiceForbiddenError`** — a plain `Error` subclass with a `code: "FORBIDDEN"` field. REST routes catch it and return 403; MCP tools catch it and return `err(McpErrorCode.FORBIDDEN, ...)`. This keeps the delivery layers thin.

**`recalculateObjectiveScore` replaces this pattern (currently in 3 places):**
```ts
const krs = await prisma.keyResult.findMany({
  where: { objectiveId },
  select: { score: true, weight: true },
});
await prisma.objective.update({
  where: { id: objectiveId },
  data: { score: calculateObjectiveScore(krs) },
});
```

---

### `src/lib/services/cycles.ts`

```ts
// Atomically deactivate all other cycles, then activate the target.
// Wraps both writes in $transaction.
export async function activateCycle(
  cycleId: string,
  tenantId: string,
  prisma: PrismaClient,
): Promise<Cycle>
```

REST `cycles/[id]/status` PATCH currently runs two sequential `updateMany`/`update` without a transaction. This service wraps them in `$transaction` (matching MCP's existing behaviour — MCP was already correct).

---

### `src/lib/services/users.ts`

```ts
export interface UserListQuery {
  tenantId: string;
  search?: string;
  isActive?: boolean;   // defaults to undefined (no filter) for REST, true for MCP
  managerId?: string;
}

export interface UserListItem {
  id: string; name: string | null; email: string;
  role: string; isActive: boolean; joinDate: Date | null;
  image: string | null; managerId: string | null;
}

export async function listUsers(
  query: UserListQuery,
  prisma: PrismaClient,
): Promise<UserListItem[]>
```

Canonical field set includes everything both callers need. MCP caller passes `isActive: true`; REST caller passes no `isActive` (returns all). Pagination (skip/take) stays in the REST route — it's a delivery concern, not business logic.

---

## Error handling contract

```ts
// src/lib/services/errors.ts
export class ServiceForbiddenError extends Error {
  readonly code = "FORBIDDEN";
  constructor(message: string) { super(message); this.name = "ServiceForbiddenError"; }
}
```

**REST route** catches `ServiceForbiddenError`:
```ts
} catch (e) {
  if (e instanceof ServiceForbiddenError) return NextResponse.json({ error: e.message }, { status: 403 });
  throw e;
}
```

**MCP tool** catches `ServiceForbiddenError`:
```ts
} catch (e) {
  if (e instanceof ServiceForbiddenError) return err(McpErrorCode.FORBIDDEN, e.message);
  return handleDbError(e, "key_result.update");
}
```

## File map

| File | Change |
|---|---|
| `src/lib/services/errors.ts` | **New** — `ServiceForbiddenError` |
| `src/lib/services/key-results.ts` | **New** — `recalculateObjectiveScore`, `assertCanEditKr`, `assertCanDeleteKr` |
| `src/lib/services/cycles.ts` | **New** — `activateCycle` |
| `src/lib/services/users.ts` | **New** — `listUsers` |
| `src/app/api/key-results/[id]/route.ts` | **Update** — use service for score recalc + RBAC |
| `src/app/api/cycles/[id]/status/route.ts` | **Update** — use `activateCycle` |
| `src/app/api/admin/users/route.ts` | **Update** — use `listUsers` |
| `src/app/api/mcp/tools/key_result.ts` | **Update** — use service for score recalc + RBAC |
| `src/app/api/mcp/tools/cycle.ts` | **Update** — use `activateCycle` |
| `src/app/api/mcp/tools/user.ts` | **Update** — use `can()` + `listUsers` |
