# Tasks: feedback-ux-improvements

## Tasks

### Wave 1 (no dependencies)

- [x] `T1` — Schema migration: add reminderSentAt + FEEDBACK_REMINDER
  - Files: `prisma/schema.prisma`, `prisma/migrations/`
  - Estimate: small
  - Details: Add `reminderSentAt DateTime?` field to `FeedbackResponse` model. Add `FEEDBACK_REMINDER` to `NotificationType` enum. Run `npx prisma migrate dev --name add-feedback-reminder-fields` to generate migration.

- [x] `T2` — Include structuredData and template in inbox response
  - Files: `src/app/api/feedback-responses/inbox/route.ts`
  - Estimate: small
  - Details: In the `findMany` include, add `template: { select: { id: true, name: true, schema: true } }` to the `feedbackRequest` include block. The `FeedbackResponse` scalar fields (including `structuredData`) are already returned since no `select` is used on the top-level model — just confirm this and add the template relation.

- [x] `T3` — Create feedback management page under HR dashboard
  - Files: `src/app/dashboard/hr/feedback/page.tsx`, `src/app/dashboard/hr/feedback/FeedbackHrClient.tsx`
  - Estimate: small
  - Details: Create new server page at `src/app/dashboard/hr/feedback/page.tsx`. Auth gate with `can(role, "manage:feedback-requests")`. Fetch active users from DB. Render `FeedbackHrClient`. Create `FeedbackHrClient.tsx` by copying `src/app/admin/feedback/FeedbackAdminClient.tsx` and updating any internal `href` strings from `/dashboard/admin/feedback-*` → `/dashboard/hr/feedback-*`.

- [x] `T4` — Move feedback-requests and feedback-templates to HR dashboard
  - Files: `src/app/dashboard/hr/feedback-requests/`, `src/app/dashboard/hr/feedback-templates/`, `src/app/dashboard/admin/feedback-requests/page.tsx`, `src/app/dashboard/admin/feedback-templates/page.tsx`
  - Estimate: small
  - Details: Copy the full directory trees from `src/app/dashboard/admin/feedback-requests/` and `src/app/dashboard/admin/feedback-templates/` to `src/app/dashboard/hr/`. Update all internal links (href, Link components) within the copied files from `/dashboard/admin/` → `/dashboard/hr/`. Replace `src/app/dashboard/admin/feedback-requests/page.tsx` and `src/app/dashboard/admin/feedback-templates/page.tsx` with redirect-only pages: `import { redirect } from "next/navigation"; export default function Page() { redirect("/dashboard/hr/feedback-requests"); }` (and same for feedback-templates). Remove the copied-away files from `admin/` subdirs (keep only the redirect page.tsx).

### Wave 2 (depends on Wave 1)

- [x] `T5` — Feedback reminder library
  - Files: `src/lib/feedback-reminders.ts`
  - Estimate: small
  - Depends: T1
  - Details: Create `sendFeedbackReminders(tenantId: string): Promise<number>`. Find `FeedbackResponse` records where `status=PENDING`, `reminderSentAt=null`, `feedbackRequest.status=OPEN`, `feedbackRequest.dueAt` is between `new Date()` and `new Date(Date.now() + 3*24*60*60*1000)`, `feedbackRequest.tenantId=tenantId`. Include `feedbackRequest.employee.name` for message. For each result call `createNotification(respondentId, tenantId, "FEEDBACK_REMINDER", \`⏰ Reminder: your feedback response for ${employeeName} is due in 3 days\`, "/feedback/inbox")`. Then batch `updateMany` to set `reminderSentAt=new Date()` for all ids processed. Return count.

- [x] `T6` — Template schema validation on feedback response submit
  - Files: `src/app/api/feedback-responses/[id]/route.ts`
  - Estimate: small
  - Depends: T1
  - Details: (1) Change `findUnique` to include `feedbackRequest: { include: { template: true } }`. (2) Add `structuredData: z.record(z.unknown()).optional()` to `SubmitResponseSchema`. (3) Add local `validateStructuredData(data, templateSchema)` function — see design.md for exact implementation. (4) After parsing, when not declining: if `existing.feedbackRequest.template` is set and `structuredData` is absent → 400 `{ error: { structuredData: ["required when template is attached"] } }`; if present, run `validateStructuredData` → 400 on error. (5) Pass `structuredData: structuredData ?? null` to the `feedbackResponse.update` data object.

- [~] `T7` — Add Feedback nav link to HR dashboard and redirect old admin feedback route
  - Files: `src/app/dashboard/hr/layout.tsx`, `src/app/admin/feedback/page.tsx`, `src/app/admin/feedback/FeedbackAdminClient.tsx`
  - Estimate: small
  - Depends: T3, T4
  - Details: (1) Open `src/app/dashboard/hr/layout.tsx` (or whatever file renders the HR sidebar nav). Add a nav link for "Feedback" pointing to `/dashboard/hr/feedback`. Match style of existing HR nav links. (2) Replace `src/app/admin/feedback/page.tsx` content with: `import { redirect } from "next/navigation"; export default function FeedbackAdminRedirect() { redirect("/dashboard/hr/feedback"); }` — remove the auth/DB logic since the redirect happens before render. (3) Delete `src/app/admin/feedback/FeedbackAdminClient.tsx` (now dead code — its content was migrated to `FeedbackHrClient.tsx` in T3).

### Wave 3 (depends on Wave 2)

- [ ] `T8` — Cron route for feedback reminders
  - Files: `src/app/api/cron/feedback-reminders/route.ts`
  - Estimate: small
  - Depends: T5
  - Details: Create `POST` handler following exact pattern of `src/app/api/cron/checkin-reminders/route.ts`. Import `sendFeedbackReminders` from `@/lib/feedback-reminders`. Secure with `CRON_SECRET` Bearer check → 401. Fetch all active tenants. `Promise.all` map over tenants calling `sendFeedbackReminders`. Return `{ results: [{ tenantId, reminders }], totalReminders }`.
