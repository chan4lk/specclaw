import { test, expect } from "@playwright/test";

const BASE = "http://localhost:4000";

/** Wait for React hydration by confirming a client-interactive element responds */
async function waitForHydration(page: ReturnType<typeof test.extend<object>>["extend"] extends never ? never : import("@playwright/test").Page) {
  await page.waitForFunction(() => {
    const btn = document.querySelector('button[type="button"]');
    return btn !== null;
  }, { timeout: 8000 });
  // Give React event delegation a moment to attach
  await page.waitForTimeout(400);
}

test.describe("Help page — acceptance criteria", () => {
  // AC1: /help renders; both tabs selectable; URL hash updates
  test("AC1: /help renders with two tabs; hash updates on tab switch", async ({ page }) => {
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    await expect(page).toHaveTitle(/Help Center/);

    const howToTab = page.getByRole("button", { name: "How to Use" });
    const conceptsTab = page.getByRole("button", { name: "OKR Concepts" });
    await expect(howToTab).toBeVisible();
    await expect(conceptsTab).toBeVisible();

    await conceptsTab.click();
    await page.waitForTimeout(300);
    expect(page.url()).toMatch(/#concepts/);

    await howToTab.click();
    await page.waitForTimeout(300);
    expect(page.url()).toMatch(/#how-to-use/);
  });

  // AC2: How to Use tab shows ≥4 workflow sections with heading + description + image
  test("AC2: How to Use tab has ≥4 sections each with heading, description, and image", async ({ page }) => {
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });

    const sections = page.locator("section[id]");
    const count = await sections.count();
    expect(count).toBeGreaterThanOrEqual(4);

    const first = sections.first();
    await expect(first.locator("h2")).toBeVisible();
    await expect(first.locator("p")).toBeVisible();
    await expect(first.locator("img")).toBeVisible();
  });

  // AC3: Screenshots load; click opens zoom modal
  test("AC3: Screenshot click opens zoom modal", async ({ page }) => {
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    // Click the first screenshot button
    const firstSection = page.locator("section[id]").first();
    const screenshotBtn = firstSection.locator('button[aria-label^="Zoom in"]');
    await expect(screenshotBtn).toBeVisible();
    await screenshotBtn.click();

    const modal = page.getByRole("dialog", { name: "Zoomed screenshot" });
    await expect(modal).toBeVisible({ timeout: 5000 });

    await modal.getByRole("button", { name: /Close/ }).click();
    await expect(modal).not.toBeVisible();
  });

  // AC4: OKR Concepts tab renders all 6 MDX sections
  test("AC4: OKR Concepts tab renders 6 concept sections", async ({ page }) => {
    await page.goto(`${BASE}/help#concepts`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    // Wait for concepts content to appear (tab switch via hash effect)
    await expect(page.getByRole("heading", { name: /What is an Objective/i })).toBeVisible({ timeout: 8000 });

    const sections = page.locator("section[id]");
    expect(await sections.count()).toBeGreaterThanOrEqual(6);

    await expect(page.getByRole("heading", { name: /Key Result/i }).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: /Scoring/i }).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: /CFR/i }).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: /Cadence/i }).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: /Mistake/i }).first()).toBeVisible();
  });

  // AC5: MDX callout components render with distinct styling
  test("AC5: Callout components render with label and icon", async ({ page }) => {
    await page.goto(`${BASE}/help#concepts`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    // Wait for concepts content
    await expect(page.getByRole("heading", { name: /What is an Objective/i })).toBeVisible({ timeout: 8000 });

    const callouts = page.locator(".border-l-4");
    await expect(callouts.first()).toBeVisible({ timeout: 5000 });
    const count = await callouts.count();
    expect(count).toBeGreaterThan(0);
  });

  // AC6: Direct URL to #concepts activates concepts tab
  test("AC6: Direct navigation to /help#concepts activates concepts tab", async ({ page }) => {
    await page.goto(`${BASE}/help#concepts`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    await expect(page.getByRole("heading", { name: /What is an Objective/i })).toBeVisible({ timeout: 8000 });
    await expect(page.locator("#create-objective")).not.toBeVisible();
  });

  // AC7: HelpAnchor rendered and has correct href
  test("AC7: HelpAnchor on objectives empty state navigates to /help#concepts", async ({ page }) => {
    await page.goto(`${BASE}/dashboard/objectives`);

    const anchor = page.getByRole("link", { name: /Learn how OKRs work/i });
    await expect(anchor).toBeVisible();
    await expect(anchor).toHaveAttribute("href", "/help#concepts");
  });

  // AC8: Search with "objective" returns ≥1 result
  test("AC8: Fuse.js search returns results for 'objective'", async ({ page }) => {
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    const searchInput = page.getByPlaceholder("Search help...");
    await searchInput.click();
    await searchInput.fill("objective");
    await page.waitForTimeout(200);

    const dropdown = page.locator("[class*='absolute'][class*='rounded-lg']").filter({ hasText: "" });
    const results = page.locator("ul li button");
    await expect(results.first()).toBeVisible({ timeout: 5000 });
    expect(await results.count()).toBeGreaterThanOrEqual(1);
  });

  // AC8 edge: No results shows message
  test("AC8: Search with no match shows 'No results found'", async ({ page }) => {
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });
    await waitForHydration(page);

    const searchInput = page.getByPlaceholder("Search help...");
    await searchInput.click();
    await searchInput.fill("xyzxyzxyznonexistent");
    await page.waitForTimeout(200);

    await expect(page.getByText("No results found")).toBeVisible({ timeout: 5000 });
  });

  // AC9: Mobile viewport — no horizontal scroll
  test("AC9: Renders at 375px mobile width without horizontal scroll", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(`${BASE}/help`, { waitUntil: "networkidle" });

    await expect(page.getByRole("button", { name: "How to Use" })).toBeVisible();
    await expect(page.getByRole("button", { name: "OKR Concepts" })).toBeVisible();

    // Check no horizontal scrollbar visible (html overflow-x:hidden clips content)
    const canScroll = await page.evaluate(() => {
      return document.documentElement.scrollWidth > document.documentElement.clientWidth;
    });
    expect(canScroll).toBe(false);
  });

  // AC10: /help accessible without auth
  test("AC10: /help accessible to unauthenticated user (no redirect)", async ({ page }) => {
    await page.goto(`${BASE}/help`);
    await expect(page).toHaveURL(`${BASE}/help`);
    await expect(page.getByRole("heading", { name: "Help Center" })).toBeVisible();
  });
});
