# Tasks: hr360-structured-feedback-okr

## Tasks

### Wave 1 (no dependencies)
- [x] `T1` — Prisma schema: add FeedbackTemplate model, templateId on FeedbackRequest, structuredData on FeedbackResponse; generate and apply migration
  - Files: `prisma/schema.prisma`
  - Estimate: small

### Wave 2 (depends on Wave 1)
- [x] `T2` — Template management API: GET list, POST create, GET by id, PATCH, DELETE (with active-request guard)
  - Files: `src/app/api/admin/feedback-templates/route.ts`, `src/app/api/admin/feedback-templates/[id]/route.ts`
  - Depends: T1
  - Estimate: medium
- [x] `T3` — HR results API: GET /api/admin/feedback-requests/[id]/results with de-anonymized responses and per-category aggregates
  - Files: `src/app/api/admin/feedback-requests/[id]/results/route.ts`
  - Depends: T1
  - Estimate: medium
- [x] `T4` — Employee results API: GET /api/feedback-results/[requestId] with anonymized aggregate + 423 lock gate
  - Files: `src/app/api/feedback-results/[requestId]/route.ts`
  - Depends: T1
  - Estimate: small
- [x] `T5` — MCP feedback tool updates: add structured param to submit action; add to_okrs and create_okrs action handlers; update FeedbackSchema enum
  - Files: `src/app/api/mcp/tools/feedback.ts`
  - Depends: T1
  - Estimate: medium

### Wave 3 (depends on Wave 2)
- [x] `T6` — MCP Prompts capability: create prompts.ts (registerFeedbackPrompts, buildTemplatePromptText, FEEDBACK_TO_OKRS_PROMPT); make createMcpServer async; await in route.ts
  - Files: `src/app/api/mcp/prompts.ts`, `src/app/api/mcp/tools/server.ts`, `src/app/api/mcp/route.ts`
  - Depends: T2
  - Estimate: medium
- [x] `T7` — HR results UI: server + client component showing per-respondent score table with aggregate row and comments
  - Files: `src/app/dashboard/admin/feedback-requests/[id]/results/page.tsx`, `src/app/dashboard/admin/feedback-requests/[id]/results/HrResultsClient.tsx`
  - Depends: T3
  - Estimate: medium
- [x] `T8` — Employee results UI: server + client component showing locked state and anonymized aggregate scores with Recharts bar chart
  - Files: `src/app/dashboard/feedback/results/[requestId]/page.tsx`, `src/app/dashboard/feedback/results/[requestId]/EmployeeResultsClient.tsx`
  - Depends: T4
  - Estimate: medium
- [x] `T9` — Template management UI: list page with create/edit/delete modal; category + sub-item editor
  - Files: `src/app/dashboard/admin/feedback-templates/page.tsx`, `src/app/dashboard/admin/feedback-templates/TemplatesClient.tsx`
  - Depends: T2
  - Estimate: medium

### Wave 4 (depends on Wave 3)
- [x] `T10` — Extend FeedbackRequest create form with optional template dropdown; extend POST /api/admin/feedback-requests to accept templateId
  - Files: `src/app/admin/feedback/FeedbackAdminClient.tsx`, `src/app/api/admin/feedback-requests/route.ts`
  - Depends: T2, T9
  - Estimate: small
