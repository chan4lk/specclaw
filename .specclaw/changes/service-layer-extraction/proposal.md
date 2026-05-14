# Proposal: Service Layer Extraction — Eliminate MCP/API Duplication

**Created:** 2026-05-09
**Status:** 🟡 Draft

## Problem

The MCP tools (`src/app/api/mcp/tools/`) and the REST API routes (`src/app/api/`) both talk directly to Prisma. Business logic is duplicated in both delivery paths, causing:

1. **Objective score recalculation** — identical `findMany → calculateObjectiveScore → update` block exists in 4 places (MCP `handleCheckIn`, REST `key-results/[id]` PUT, REST `key-results/[id]` DELETE, REST `key-results/[id]/score`)
2. **KR/Objective RBAC guards** — the "owner OR edit:any-objective" pattern is copy-pasted across MCP and REST independently
3. **User field sets have diverged** — MCP `user.list` omits `isActive`, `joinDate`, `image`; REST includes them. MCP filters `isActive: true`; REST does not
4. **RBAC style inconsistency** — MCP tools use `ctx.role !== "TENANT_ADMIN"` (explicit, 5× in user.ts); REST routes use `can(role, "manage:users")`. Adding a new admin-level role requires touching MCP separately
5. **Cycle activation** — MCP wraps in `$transaction`; REST does not, creating a race window

Any business-rule change (new role, new field, scoring tweak) must be applied in two places and can silently diverge.

## Proposed Solution

Introduce a **thin service layer** at `src/lib/services/` — plain TypeScript modules with no HTTP or MCP SDK dependencies. Both REST routes and MCP tools call the same service functions. The delivery layers become thin adapters:

```
REST route  →  parse HTTP request  →  call service  →  NextResponse.json()
MCP tool    →  parse Zod input     →  call service  →  toMcpContent()
```

Three service files address the identified duplications:

**`src/lib/services/key-results.ts`**
- `recalculateObjectiveScore(objectiveId, prisma)` — single source for the score recalc pattern
- `assertKrEditAccess(kr, ctx)` / `assertKrDeleteAccess(kr, ctx)` — shared RBAC guards

**`src/lib/services/cycles.ts`**
- `activateCycle(cycleId, tenantId, prisma)` — transactional deactivate-then-activate with single implementation

**`src/lib/services/users.ts`**
- `listUsers(query, ctx)` — canonical field set, consistent `isActive` filter behaviour

Then update MCP tools and REST routes to call services instead of inline Prisma.

## Scope

### In Scope
- `src/lib/services/key-results.ts` — recalc + RBAC helpers
- `src/lib/services/cycles.ts` — activation helper
- `src/lib/services/users.ts` — list query helper
- Update `src/app/api/mcp/tools/key_result.ts` to use service
- Update `src/app/api/mcp/tools/cycle.ts` to use service
- Update `src/app/api/mcp/tools/user.ts` to use `can()` consistently + service
- Update `src/app/api/key-results/[id]/route.ts` to use service
- Update `src/app/api/cycles/[id]/status/route.ts` to use service
- Update `src/app/api/admin/users/route.ts` to use service

### Out of Scope
- Refactoring objective-level CRUD (low duplication risk today)
- Report MCP tool (no REST equivalent to unify with)
- PowerAutomate routes
- Any new features or behaviour changes — **pure refactor, no functional change**

## Impact

- **Files affected:** ~9 (estimated)
- **Complexity:** medium
- **Risk:** low — behaviour-preserving refactor; existing E2E tests validate correctness

## Open Questions

None — approach is clear from audit.

---

**To proceed:** Review this proposal and approve to begin planning.
