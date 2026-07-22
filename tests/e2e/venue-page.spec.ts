import { test, expect, type Page } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

const MOCK_LAT = 38.8769326;
const MOCK_LNG = -77.0893094;

const RUN_ID = Date.now().toString(36);
const PASSWORD = "TestPassword123!";

const FIXTURE_SEARCH = `Playwright Venue Search Target ${RUN_ID}`;
const FIXTURE_MOBILE = `Playwright Venue Mobile Target ${RUN_ID}`;
const FIXTURE_DIRECT = `Playwright Venue Direct Target ${RUN_ID}`;
const FIXTURE_WANT_TO_GO = `Playwright Venue WantToGo Target ${RUN_ID}`;
const FIXTURE_SHARE = `Playwright Venue Share Target ${RUN_ID}`;
const FIXTURE_SITEMAP_INCLUDED = `Playwright Venue Sitemap Included ${RUN_ID}`;
const FIXTURE_SITEMAP_NEEDS_REVIEW = `Playwright Venue Sitemap NeedsReview ${RUN_ID}`;
const FIXTURE_SITEMAP_CLOSED = `Playwright Venue Sitemap Closed ${RUN_ID}`;

const fixtureIds: Record<string, string> = {};
let categoryId: string;

async function createFixtureEntity(
  name: string,
  overrides: { needs_review?: boolean; status?: string } = {}
): Promise<string> {
  const { data, error } = await supabase
    .from("entities")
    .insert({
      name,
      address: "Arlington, VA",
      location: `SRID=4326;POINT(${MOCK_LNG} ${MOCK_LAT})`,
      ...overrides,
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(`Failed to insert fixture "${name}": ${error?.message}`);

  const { error: linkError } = await supabase
    .from("entity_categories")
    .insert({ entity_id: data.id, category_id: categoryId });
  if (linkError) throw new Error(`Failed to tag fixture "${name}": ${linkError.message}`);

  return data.id;
}

type TestUser = { id: string; email: string; handle: string };

const wantToGoUser: TestUser = {
  id: "",
  email: `test+venuewtg-${RUN_ID}@example.com`,
  handle: `pw-venue-wtg-${RUN_ID}`,
};

async function createTestUser(user: TestUser) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: user.email,
    password: PASSWORD,
    email_confirm: true,
  });
  if (error || !data.user) throw new Error(`Failed to create ${user.email}: ${error?.message}`);
  user.id = data.user.id;

  const { error: profileError } = await supabase
    .from("profiles")
    .update({ handle: user.handle, display_name: user.handle })
    .eq("id", user.id);
  if (profileError) throw new Error(`Failed to set profile for ${user.email}: ${profileError.message}`);
}

async function signIn(page: Page, user: TestUser) {
  await page.goto("/sign-in");
  await page.locator("#email").fill(user.email);
  await page.locator("#password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await page.waitForURL("/", { timeout: 15_000 });

  // First sign-in for a user with no home location shows a full-screen
  // prompt that intercepts every subsequent click - see the same handling
  // in entity-map-star-popup.spec.ts.
  const skipButton = page.getByRole("button", { name: "Skip for now" });
  await expect(skipButton).toBeVisible({ timeout: 10_000 });
  await skipButton.click();
  await expect(page.getByText("Set your home location?")).toHaveCount(0);
}

async function searchByName(page: Page, name: string) {
  await page.goto("/search");
  await page.locator("#name").fill(name);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText(name)).toBeVisible({ timeout: 15_000 });
}

async function getDefaultListId(userId: string): Promise<string | null> {
  const { data } = await supabase
    .from("lists")
    .select("id, name, visibility")
    .eq("owner_id", userId)
    .eq("is_default_list", true)
    .maybeSingle();
  return data?.id ?? null;
}

async function isInList(listId: string, entityId: string): Promise<boolean> {
  const { data } = await supabase
    .from("list_items")
    .select("entity_id")
    .eq("list_id", listId)
    .eq("entity_id", entityId)
    .maybeSingle();
  return !!data;
}

test.use({
  geolocation: { latitude: MOCK_LAT, longitude: MOCK_LNG },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  const { data: category, error: catError } = await supabase
    .from("categories")
    .select("id")
    .eq("slug", "restaurants")
    .single();
  if (catError || !category) throw new Error(`Could not find "restaurants" category: ${catError?.message}`);
  categoryId = category.id;

  await createTestUser(wantToGoUser);

  fixtureIds.search = await createFixtureEntity(FIXTURE_SEARCH);
  fixtureIds.mobile = await createFixtureEntity(FIXTURE_MOBILE);
  fixtureIds.direct = await createFixtureEntity(FIXTURE_DIRECT);
  fixtureIds.wantToGo = await createFixtureEntity(FIXTURE_WANT_TO_GO);
  fixtureIds.share = await createFixtureEntity(FIXTURE_SHARE);
  fixtureIds.sitemapIncluded = await createFixtureEntity(FIXTURE_SITEMAP_INCLUDED);
  fixtureIds.sitemapNeedsReview = await createFixtureEntity(FIXTURE_SITEMAP_NEEDS_REVIEW, {
    needs_review: true,
  });
  fixtureIds.sitemapClosed = await createFixtureEntity(FIXTURE_SITEMAP_CLOSED, {
    status: "permanently_closed",
  });
});

test.afterAll(async () => {
  const defaultListId = await getDefaultListId(wantToGoUser.id);
  if (defaultListId) {
    await supabase.from("list_items").delete().eq("list_id", defaultListId);
    await supabase.from("lists").delete().eq("id", defaultListId);
  }
  for (const id of Object.values(fixtureIds)) {
    await supabase.from("entity_categories").delete().eq("entity_id", id);
    await supabase.from("stars").delete().eq("entity_id", id);
    await supabase.from("entities").delete().eq("id", id);
  }
  if (wantToGoUser.id) await supabase.auth.admin.deleteUser(wantToGoUser.id);
});

test.describe("desktop viewport", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("clicking a venue from search results opens a dimmed modal overlay with an X close button, updates the URL, and preserves the page behind it", async ({
    page,
  }) => {
    await searchByName(page, FIXTURE_SEARCH);

    await page.getByRole("link", { name: FIXTURE_SEARCH }).click();

    await expect(page).toHaveURL(new RegExp(`/venue/${fixtureIds.search}$`));
    // The search page behind the modal is still mounted, not replaced.
    await expect(page.locator("#name")).toHaveValue(FIXTURE_SEARCH);

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(FIXTURE_SEARCH)).toBeVisible();
    await expect(page.getByRole("button", { name: "Close" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Back" })).toBeHidden();

    await page.getByRole("button", { name: "Close" }).click();
    await expect(page).toHaveURL(/\/search$/);
    await expect(page.getByRole("dialog")).toHaveCount(0);
    // Still there - closing the modal didn't reset the search.
    await expect(page.locator("#name")).toHaveValue(FIXTURE_SEARCH);
  });

  test("directly navigating to /venue/[id] renders the full standalone page, not a modal", async ({
    page,
  }) => {
    await page.goto(`/venue/${fixtureIds.direct}`);

    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(page.getByText(FIXTURE_DIRECT)).toBeVisible();
    // The full page keeps the normal app chrome (desktop sidebar nav).
    await expect(page.locator('nav[aria-label="Main"]:visible')).toHaveCount(1);
  });
});

test.describe("mobile viewport", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("opens full-screen with a back button that returns to the prior view, not a dimmed slide-over", async ({
    page,
  }) => {
    await searchByName(page, FIXTURE_MOBILE);

    await page.getByRole("link", { name: FIXTURE_MOBILE }).click();
    await expect(page).toHaveURL(new RegExp(`/venue/${fixtureIds.mobile}$`));

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(FIXTURE_MOBILE)).toBeVisible();
    await expect(page.getByRole("button", { name: "Back" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Close" })).toBeHidden();

    await page.getByRole("button", { name: "Back" }).click();
    await expect(page).toHaveURL(/\/search$/);
    await expect(page.getByRole("dialog")).toHaveCount(0);
    // Back means back to the actual prior view, not a blank/reset state.
    await expect(page.locator("#name")).toHaveValue(FIXTURE_MOBILE);
  });
});

test.describe("Want to Go", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("creates a default list on first use and toggles correctly afterward", async ({ page }) => {
    expect(await getDefaultListId(wantToGoUser.id)).toBeNull();

    await signIn(page, wantToGoUser);
    await page.goto(`/venue/${fixtureIds.wantToGo}`);

    const wantToGoButton = page.getByRole("button", { name: "Want to Go", exact: true });
    await expect(wantToGoButton).toBeEnabled();
    await wantToGoButton.click();

    await expect(page.getByRole("button", { name: "Remove from Want to Go" })).toBeVisible({
      timeout: 10_000,
    });

    const listId = await getDefaultListId(wantToGoUser.id);
    expect(listId).not.toBeNull();
    const { data: listRow } = await supabase
      .from("lists")
      .select("name, visibility, is_default_list")
      .eq("id", listId!)
      .single();
    expect(listRow).toMatchObject({
      name: "Want to Go",
      visibility: "private",
      is_default_list: true,
    });
    expect(await isInList(listId!, fixtureIds.wantToGo)).toBe(true);

    // Toggle it off - same default list, item removed.
    await page.getByRole("button", { name: "Remove from Want to Go" }).click();
    await expect(
      page.getByRole("button", { name: "Want to Go", exact: true })
    ).toBeVisible({ timeout: 10_000 });
    expect(await isInList(listId!, fixtureIds.wantToGo)).toBe(false);
    // The list itself isn't deleted by toggling an item off it.
    expect(await getDefaultListId(wantToGoUser.id)).toBe(listId);

    // Persists correctly across a reload too.
    await page.reload();
    await expect(
      page.getByRole("button", { name: "Want to Go", exact: true })
    ).toBeVisible({ timeout: 10_000 });
  });
});

test.describe("Share", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("falls back to a Copy link / Email dropdown when the Web Share API is unsupported", async ({
    page,
  }) => {
    await page.goto(`/venue/${fixtureIds.share}`);

    await page.getByRole("button", { name: "Share", exact: true }).click();
    await expect(page.getByRole("button", { name: "Copy link" })).toBeVisible();
    await expect(page.getByRole("button", { name: "Email" })).toBeVisible();
  });

  test("uses navigator.share directly when the Web Share API is supported", async ({ page }) => {
    await page.addInitScript(() => {
      (window as unknown as { __shareCalls: unknown[] }).__shareCalls = [];
      Object.defineProperty(window.navigator, "share", {
        configurable: true,
        value: async (data: unknown) => {
          (window as unknown as { __shareCalls: unknown[] }).__shareCalls.push(data);
        },
      });
    });

    await page.goto(`/venue/${fixtureIds.share}`);
    await page.getByRole("button", { name: "Share", exact: true }).click();

    await expect(page.getByRole("button", { name: "Copy link" })).toHaveCount(0);
    const calls = await page.evaluate(
      () => (window as unknown as { __shareCalls: { title: string; url: string }[] }).__shareCalls
    );
    expect(calls).toHaveLength(1);
    expect(calls[0].title).toBe(FIXTURE_SHARE);
    expect(calls[0].url).toContain(`/venue/${fixtureIds.share}`);
  });
});

test.describe("sitemap", () => {
  test("only includes reviewed, non-closed entities", async ({ request }) => {
    const res = await request.get("/sitemap/0.xml");
    expect(res.ok()).toBe(true);
    const body = await res.text();

    expect(body).toContain(`/venue/${fixtureIds.sitemapIncluded}`);
    expect(body).not.toContain(`/venue/${fixtureIds.sitemapNeedsReview}`);
    expect(body).not.toContain(`/venue/${fixtureIds.sitemapClosed}`);
  });
});
