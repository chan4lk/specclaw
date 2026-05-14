# Spec: Service Layer Extraction

**Change:** service-layer-extraction
**Created:** 2026-05-09

## Functional Requirements

### FR-1: Single source of truth for objective score recalculation
The pattern "fetch sibling KRs → calculateObjectiveScore → update objective.score" must exist in exactly one place. All callers (REST PUT, REST DELETE, MCP check_in) must use that single implementation.

### FR-2: Single source of truth for KR edit/delete authorization
The ownership-or-admin guard ("owner OR `edit:any-objective`") must be defined once. Both the REST route and MCP tool must call the same function.

### FR-3: Single source of truth for cycle activation
The transactional deactivate-all-others-then-activate pattern must exist in one place, used by both the REST PATCH and MCP `set_active`.

### FR-4: Canonical user list query
`listUsers` must return a consistent field set: `id, name, email, role, isActive, joinDate, image, managerId`. Both REST and MCP call this function; callers may project a subset after the fact but the underlying query is shared.

### FR-5: Consistent RBAC in MCP user tool
Replace all `ctx.role !== "TENANT_ADMIN" && ctx.role !== "SUPER_ADMIN"` checks in `user.ts` with `!can(ctx.role, "manage:users")` so the permission system is the single source for role eligibility.

## Acceptance Criteria

- AC-1: `recalculateObjectiveScore(objectiveId, prisma)` exists in `src/lib/services/key-results.ts` and is the only place this query+update pattern appears
- AC-2: `assertCanEditKr` and `assertCanDeleteKr` helpers exist in `src/lib/services/key-results.ts` and are called from both REST and MCP
- AC-3: `activateCycle(cycleId, tenantId, prisma)` exists in `src/lib/services/cycles.ts`, wraps both deactivation and activation in a `$transaction`, and is called from both REST and MCP
- AC-4: `listUsers(query, ctx)` exists in `src/lib/services/users.ts` with the canonical field set and is called from both REST and MCP
- AC-5: `user.ts` MCP tool contains no `ctx.role !== "TENANT_ADMIN"` string
- AC-6: No behaviour change — existing E2E tests pass unchanged
- AC-7: TypeScript compiles without errors (`bun run build`)

## Non-Goals

- No new features
- No changes to API response shapes visible to clients
- No migration of objective CRUD, CFR, notifications, or PowerAutomate routes
