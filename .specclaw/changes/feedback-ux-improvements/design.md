# Design: feedback-ux-improvements

## Architecture Overview

Three independent workstreams that can be executed in parallel (waves 1+2 share a schema dependency):

1. **Schema + migration** (blocker for cron lib and validation)
2. **Cron reminder** (depends on schema)
3. **Template validation + inbox fix** (depends on schema for `reminderSentAt`-free; validation is independent)
4. **UI migration** (fully independent of 1-3)

---

## Technical Approach

### 1. Schema Changes (`prisma/schema.prisma`)

Add to `FeedbackResponse`:
```prisma
reminderSentAt  DateTime?
```

Add to `NotificationType` enum:
```prisma
FEEDBACK_REMINDER
```

Run: `npx prisma migrate dev --name add-feedback-reminder-fields`

---

### 2. Feedback Reminder Library (`src/lib/feedback-reminders.ts`)

Pattern mirrors `src/lib/checkin-reminders.ts`.

```ts
export async function sendFeedbackReminders(tenantId: string): Promise<number>
```

Logic:
1. Compute `threeDaysFromNow = new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)`
2. Query: `FeedbackResponse` where `status=PENDING`, `reminderSentAt=null`, `feedbackRequest.status=OPEN`, `feedbackRequest.dueAt` between `now` and `threeDaysFromNow`, `feedbackRequest.tenantId=tenantId`
3. Include `feedbackRequest.employee` (name) for notification message
4. For each: `createNotification(respondentId, tenantId, "FEEDBACK_REMINDER", "⏰ Reminder: your feedback response for [name] is due in 3 days", "/feedback/inbox")`
5. Batch update: `prisma.feedbackResponse.updateMany({ where: { id: { in: ids } }, data: { reminderSentAt: new Date() } })`
6. Return count

---

### 3. Cron Route (`src/app/api/cron/feedback-reminders/route.ts`)

Exact same shape as `checkin-reminders/route.ts`:
- `POST` handler
- `CRON_SECRET` Bearer check → 401 if missing/wrong
- `prisma.tenant.findMany({ where: { isActive: true } })`
- `Promise.all(tenants.map(t => sendFeedbackReminders(t.id)))`
- Return `{ results, totalReminders }`

---

### 4. Template Validation (`src/app/api/feedback-responses/[id]/route.ts`)

**Changes to existing `PUT` handler:**

Step 1 — load more data on the existing record lookup:
```ts
const existing = await prisma.feedbackResponse.findUnique({
  where: { id },
  include: {
    feedbackRequest: {
      include: { template: true }
    }
  }
});
```

Step 2 — extend `SubmitResponseSchema`:
```ts
const SubmitResponseSchema = z.object({
  response: z.string().min(1).optional(),
  decline: z.boolean().optional(),
  structuredData: z.record(z.unknown()).optional(),
});
```

Step 3 — after parsing, before the update, when `!decline`:
```ts
const template = existing.feedbackRequest.template;
if (template) {
  if (!structuredData) {
    return NextResponse.json(
      { error: { structuredData: ["required when template is attached"] } },
      { status: 400 }
    );
  }
  const validationError = validateStructuredData(structuredData, template.schema);
  if (validationError) {
    return NextResponse.json({ error: { structuredData: [validationError] } }, { status: 400 });
  }
}
```

Step 4 — include `structuredData` in the update:
```ts
data: { status: "RESPONDED", response, structuredData: structuredData ?? null, submittedAt: new Date() }
```

**New helper `validateStructuredData`** (defined in same file or extracted to `src/lib/feedback-validation.ts`):
```ts
type TemplateSchema = { categories: Array<{ name: string; items: Array<{ name: string }> }> };

function validateStructuredData(data: unknown, templateSchema: unknown): string | null {
  const schema = templateSchema as TemplateSchema;
  if (!schema.categories?.length) return null; // empty template = no validation
  
  const sd = data as { categories?: Array<{ name: string; items?: Array<{ name: string; score: unknown }> }> };
  if (!sd?.categories) return "structuredData.categories is required";
  
  for (const tCat of schema.categories) {
    const dCat = sd.categories.find(c => c.name === tCat.name);
    if (!dCat) return `missing category: ${tCat.name}`;
    for (const tItem of tCat.items) {
      const dItem = dCat.items?.find(i => i.name === tItem.name);
      if (!dItem) return `missing item: ${tItem.name} in category ${tCat.name}`;
      if (typeof dItem.score !== "number") return `score must be a number for item: ${tItem.name}`;
    }
  }
  return null;
}
```

---

### 5. Inbox Route Fix (`src/app/api/feedback-responses/inbox/route.ts`)

Add `structuredData` to the query (it's already on the model, just not selected):

```ts
// Currently: no select = returns all scalar fields including structuredData already
// But feedbackRequest include needs template added:
include: {
  feedbackRequest: {
    include: {
      employee: { select: { id: true, name: true, email: true, image: true } },
      template: { select: { id: true, name: true, schema: true } },  // ADD THIS
    },
  },
},
```

No `select` on `feedbackResponse` itself = all scalar fields (including `structuredData`) already returned. Just add template to feedbackRequest include.

---

### 6. UI Migration

#### New page: `src/app/dashboard/hr/feedback/page.tsx`
- Copy of `src/app/admin/feedback/page.tsx` with path updates
- Import `FeedbackHrClient` instead of `FeedbackAdminClient`

#### New client: `src/app/dashboard/hr/feedback/FeedbackHrClient.tsx`
- Copy of `src/app/admin/feedback/FeedbackAdminClient.tsx`
- Update any hardcoded paths (e.g. links to `/dashboard/admin/feedback-requests/[id]/results` → `/dashboard/hr/feedback-requests/[id]/results`)

#### Redirect: `src/app/admin/feedback/page.tsx`
Replace current content with:
```ts
import { redirect } from "next/navigation";
export default function FeedbackAdminRedirect() {
  redirect("/dashboard/hr/feedback");
}
```

#### Move directories:
- `src/app/dashboard/admin/feedback-requests/` → `src/app/dashboard/hr/feedback-requests/`
- `src/app/dashboard/admin/feedback-templates/` → `src/app/dashboard/hr/feedback-templates/`

Update all internal `href` strings in moved files from `/dashboard/admin/feedback-*` → `/dashboard/hr/feedback-*`.

Add redirects in old locations:
- `src/app/dashboard/admin/feedback-requests/page.tsx` → redirect to `/dashboard/hr/feedback-requests`
- `src/app/dashboard/admin/feedback-templates/page.tsx` → redirect to `/dashboard/hr/feedback-templates`

#### Nav update:
Find the HR dashboard sidebar/nav (likely `src/app/dashboard/hr/layout.tsx` or a sidebar component). Add:
```tsx
<Link href="/dashboard/hr/feedback">Feedback</Link>
```

---

## File Change Map

| File | Action |
|---|---|
| `prisma/schema.prisma` | Add `reminderSentAt`, `FEEDBACK_REMINDER` |
| `prisma/migrations/` | Auto-generated migration |
| `src/lib/feedback-reminders.ts` | New — reminder logic |
| `src/app/api/cron/feedback-reminders/route.ts` | New — cron endpoint |
| `src/app/api/feedback-responses/[id]/route.ts` | Extend schema + template validation |
| `src/app/api/feedback-responses/inbox/route.ts` | Add template to include |
| `src/app/dashboard/hr/feedback/page.tsx` | New — migrated server page |
| `src/app/dashboard/hr/feedback/FeedbackHrClient.tsx` | New — migrated client |
| `src/app/admin/feedback/page.tsx` | Replace with redirect |
| `src/app/admin/feedback/FeedbackAdminClient.tsx` | Delete (no longer needed) |
| `src/app/dashboard/hr/feedback-requests/` | Moved from `admin/feedback-requests/` |
| `src/app/dashboard/hr/feedback-templates/` | Moved from `admin/feedback-templates/` |
| `src/app/dashboard/admin/feedback-requests/page.tsx` | Replace with redirect |
| `src/app/dashboard/admin/feedback-templates/page.tsx` | Replace with redirect |
| `src/app/dashboard/hr/layout.tsx` or nav component | Add Feedback nav link |

---

## Dependencies & Risks

- `FEEDBACK_REMINDER` notification type requires migration — agents must run `npx prisma migrate dev` before building code that imports it
- Moving directories in Next.js App Router: old routes auto-become 404 unless redirect pages are added
- `FeedbackAdminClient.tsx` may reference `/dashboard/admin/feedback-*` paths — must audit all `href` strings
- No email in v1 — in-app only, respects `NotificationPreference`
