# Spec: feedback-ux-improvements

## Functional Requirements

### FR1 — Feedback Overdue Reminder Cron

**FR1.1** A new cron endpoint `POST /api/cron/feedback-reminders` must exist, secured by `Authorization: Bearer <CRON_SECRET>`.

**FR1.2** The endpoint finds all `FeedbackResponse` records where:
- `status = PENDING`
- `feedbackRequest.status = OPEN`
- `feedbackRequest.dueAt` is between now and now+3 days (inclusive)
- `reminderSentAt IS NULL`

**FR1.3** For each matching response, send an in-app notification to the respondent using `createNotification()` with type `FEEDBACK_REMINDER`.

**FR1.4** After sending, set `FeedbackResponse.reminderSentAt = now()`.

**FR1.5** The endpoint returns `{ results: [{ tenantId, reminders: count }], totalReminders }` — one entry per active tenant.

**FR1.6** `FeedbackResponse` gains a new optional field `reminderSentAt DateTime?` (requires migration).

**FR1.7** `NotificationType` enum gains a new value `FEEDBACK_REMINDER` (requires migration).

**FR1.8** Notification message: `"⏰ Reminder: your feedback response for [employee name] is due in 3 days"`. Link: `/feedback/inbox`.

---

### FR2 — Template Schema Validation on Submit

**FR2.1** `PUT /api/feedback-responses/[id]` must load the `feedbackRequest` with its `template` relation when checking the existing record.

**FR2.2** When `feedbackRequest.templateId` is set and `decline` is false:
- `structuredData` is **required** in the request body.
- `structuredData` must conform to the template schema: every category defined in the template must be present; every item within each category must have a numeric `score`.
- If either condition fails, return `400` with a field-level error: `{ error: { structuredData: ["<reason>"] } }`.

**FR2.3** When `feedbackRequest.templateId` is null, `structuredData` is optional (existing behavior preserved).

**FR2.4** The `SubmitResponseSchema` Zod schema is extended to accept an optional `structuredData` field (typed as `z.record(z.unknown())` at the Zod layer; structural validation is done programmatically after parsing).

**FR2.5** On successful submit, `structuredData` is saved to `FeedbackResponse.structuredData`.

**FR2.6** Template schema format (from `FeedbackTemplate.schema`):
```ts
// Expected shape of FeedbackTemplate.schema JSON
{
  categories: Array<{
    name: string;
    items: Array<{ name: string }>;
  }>
}
```
Validation checks that every `category.name` and `item.name` from the template is present in `structuredData.categories[].name` / `.items[].name` with a numeric `score`.

---

### FR3 — Include structuredData in Inbox Response

**FR3.1** `GET /api/feedback-responses/inbox` must include `structuredData` in the returned `FeedbackResponse` records.

**FR3.2** The `feedbackRequest` include must also return its `template` relation (id, name, schema) so clients can render template fields.

---

### FR4 — Move Feedback Management UI to HR Dashboard

**FR4.1** A new server page at `src/app/dashboard/hr/feedback/page.tsx` replaces `src/app/admin/feedback/page.tsx` as the primary HR feedback management surface.

**FR4.2** The new page uses the same `manage:feedback-requests` RBAC check via `can(role, "manage:feedback-requests")`.

**FR4.3** `src/app/admin/feedback/page.tsx` becomes a redirect to `/dashboard/hr/feedback` (HTTP 301 via `redirect()`).

**FR4.4** `src/app/dashboard/admin/feedback-requests/` directory is moved to `src/app/dashboard/hr/feedback-requests/`. All internal links updated.

**FR4.5** `src/app/dashboard/admin/feedback-templates/` directory is moved to `src/app/dashboard/hr/feedback-templates/`. All internal links updated.

**FR4.6** The HR dashboard navigation (sidebar/nav in `src/app/dashboard/hr/`) adds a "Feedback" link pointing to `/dashboard/hr/feedback`.

**FR4.7** Any existing nav links to `/admin/feedback`, `/dashboard/admin/feedback-requests`, or `/dashboard/admin/feedback-templates` are updated to the new paths.

---

## Acceptance Criteria

| # | Criterion | How to verify |
|---|---|---|
| AC1 | Cron endpoint exists and requires Bearer auth | `curl -X POST /api/cron/feedback-reminders` without token → 401 |
| AC2 | Cron sends notifications only to PENDING responses due within 3 days | Seed test data, call cron, check Notification table |
| AC3 | `reminderSentAt` set after send; second cron call skips same response | Call cron twice, confirm count=0 on second call |
| AC4 | Submit with templateId but no structuredData → 400 | `PUT /api/feedback-responses/[id]` without structuredData when template attached |
| AC5 | Submit with templateId + invalid structuredData → 400 with field error | Omit a required category, expect `{ error: { structuredData: [...] } }` |
| AC6 | Submit with templateId + valid structuredData → 200, data saved | Full submit, check DB |
| AC7 | Submit without templateId + no structuredData → 200 (unchanged behavior) | Existing test case |
| AC8 | Inbox GET returns structuredData and template fields | Check response shape |
| AC9 | `/admin/feedback` redirects to `/dashboard/hr/feedback` | Browser navigation |
| AC10 | `/dashboard/hr/feedback` renders for HR_VIEWER role | Login as HR_VIEWER, navigate |
| AC11 | `/dashboard/admin/feedback-requests` and `/dashboard/admin/feedback-templates` URLs updated | Old paths 404 or redirect |

---

## Edge Cases

- `dueAt` is null on a FeedbackRequest: skip that response in cron (no deadline = no reminder).
- Template schema has empty `categories` array: treat as no-template validation (structuredData not required).
- Respondent already RESPONDED or DECLINED before cron runs: filtered out by `status = PENDING`.
- SUPER_ADMIN navigating to `/dashboard/admin/feedback-requests`: receives 404 after move — redirects must be placed.
