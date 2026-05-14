# Tasks: service-layer-extraction

## Tasks

### Wave 1 (no dependencies — create service files)

- [x] `T1` — Create service error type
  - Files: `src/lib/services/errors.ts`
  - Estimate: small

- [x] `T2` — Create key-result service
  - Files: `src/lib/services/key-results.ts`
  - Estimate: small

- [x] `T3` — Create cycle service
  - Files: `src/lib/services/cycles.ts`
  - Estimate: small

- [x] `T4` — Create user list service
  - Files: `src/lib/services/users.ts`
  - Estimate: small

### Wave 2 (depends on T1, T2 — wire key-result callers)

- [~] `T5` — Update REST key-result route to use service
  - Files: `src/app/api/key-results/[id]/route.ts`
  - Depends: T1, T2
  - Estimate: small

- [~] `T6` — Update MCP key_result tool to use service
  - Files: `src/app/api/mcp/tools/key_result.ts`
  - Depends: T1, T2
  - Estimate: small

### Wave 3 (depends on T1, T3, T4 — wire cycle and user callers)

- [ ] `T7` — Update REST cycle status route to use service
  - Files: `src/app/api/cycles/[id]/status/route.ts`
  - Depends: T1, T3
  - Estimate: small

- [ ] `T8` — Update MCP cycle tool to use service
  - Files: `src/app/api/mcp/tools/cycle.ts`
  - Depends: T1, T3
  - Estimate: small

- [ ] `T9` — Update REST admin users route to use service
  - Files: `src/app/api/admin/users/route.ts`
  - Depends: T1, T4
  - Estimate: small

- [ ] `T10` — Update MCP user tool: use can() + listUsers service
  - Files: `src/app/api/mcp/tools/user.ts`
  - Depends: T1, T4
  - Estimate: small

### Wave 4 (depends on all — verify build)

- [ ] `T11` — Verify TypeScript build passes
  - Files: (no file changes — validation only)
  - Depends: T5, T6, T7, T8, T9, T10
  - Estimate: small
