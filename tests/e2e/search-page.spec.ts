import { test, expect, type Page } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// Mocked "current location" for these tests - Arlington, VA, matching the
// rest of the seed data and other e2e specs in this repo.
const MOCK_LAT = 38.8816;
const MOCK_LNG = -77.091;

// ~400 miles from the mocked location (Boston, MA) - far outside any radius
// reachable from the Discover page's slider (max 25mi), but well within the
// Search page's much larger fixed radius. Proves the name-only lookup
// really does ignore distance, not just fudge it a little.
const FAR_LAT = 42.3601;
const FAR_LNG = -71.0589;

const FIXTURE_NAME = "Playwright Test Search Target Faraway";

let fixtureEntityId: string;

test.use({
  geolocation: { latitude: MOCK_LAT, longitude: MOCK_LNG },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  // search_entities inner-joins through entity_categories, so an entity
  // with no category tag at all never matches any search - tag the
  // fixture with the "restaurants" root category so it's eligible.
  const { data: category, error: catError } = await supabase
    .from("categories")
    .select("id")
    .eq("slug", "restaurants")
    .single();
  if (catError || !category) {
    throw new Error(`Could not find "restaurants" category: ${catError?.message}`);
  }

  const { data, error } = await supabase
    .from("entities")
    .insert({
      name: FIXTURE_NAME,
      address: "Boston, MA",
      location: `SRID=4326;POINT(${FAR_LNG} ${FAR_LAT})`,
    })
    .select("id")
    .single();
  if (error || !data) {
    throw new Error(`Failed to insert search fixture: ${error?.message}`);
  }
  fixtureEntityId = data.id;

  const { error: linkError } = await supabase
    .from("entity_categories")
    .insert({ entity_id: fixtureEntityId, category_id: category.id });
  if (linkError) {
    throw new Error(`Failed to tag search fixture: ${linkError.message}`);
  }
});

test.afterAll(async () => {
  if (!fixtureEntityId) return;
  await supabase.from("entity_categories").delete().eq("entity_id", fixtureEntityId);
  await supabase.from("entities").delete().eq("id", fixtureEntityId);
});

test.describe("sidebar nav", () => {
  test("Search appears in the desktop sidebar", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto("/");

    const nav = page.locator('nav[aria-label="Main"]:visible');
    await expect(nav).toHaveCount(1);
    await expect(nav.getByRole("link", { name: "Search" })).toBeVisible();
  });

  test("Search appears in the mobile bottom tab bar", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/");

    const nav = page.locator('nav[aria-label="Main"]:visible');
    await expect(nav).toHaveCount(1);
    await expect(nav.getByRole("link", { name: "Search" })).toBeVisible();
  });
});

test.describe("Search page", () => {
  test("has only a name field and Search button - no radius/category/location controls", async ({
    page,
  }) => {
    await page.goto("/search");

    await expect(page.locator("#name")).toBeVisible();
    await expect(page.getByRole("button", { name: "Search", exact: true })).toBeVisible();

    await expect(page.locator("#radius")).toHaveCount(0);
    await expect(page.locator("#category")).toHaveCount(0);
    await expect(page.locator("#location")).toHaveCount(0);
  });

  test("finds a known restaurant by name regardless of configured distance", async ({ page }) => {
    await page.goto("/search");

    await page.locator("#name").fill(FIXTURE_NAME);
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText(FIXTURE_NAME)).toBeVisible();
  });
});

test.describe("Search page location fallback chain", () => {
  // No geolocation permission at all here (overrides the file-level grant
  // above) - requestLocation() resolves null just like a real denial,
  // without needing an actual OS-level prompt to interact with.
  test.use({ permissions: [] });

  const PASSWORD = "TestPassword123!";
  const RUN_ID = Date.now().toString(36);

  type TestUser = { id: string; email: string; handle: string };

  const homeUser: TestUser = {
    id: "",
    email: `test+searchhome-${RUN_ID}@example.com`,
    handle: `pw-search-home-${RUN_ID}`,
  };
  const noHomeUser: TestUser = {
    id: "",
    email: `test+searchnohome-${RUN_ID}@example.com`,
    handle: `pw-search-nohome-${RUN_ID}`,
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
  }

  test.beforeAll(async () => {
    await Promise.all([createTestUser(homeUser), createTestUser(noHomeUser)]);

    // ~390 miles from the FIXTURE_NAME entity (Boston, MA) - well within
    // the Search page's 500mi radius, same margin home-location.spec.ts
    // already relies on for its own Rockville, MD test data.
    await supabase
      .from("profiles")
      .update({ home_city: "Rockville", home_state: "MD" })
      .eq("id", homeUser.id);
  });

  test.afterAll(async () => {
    for (const user of [homeUser, noHomeUser]) {
      if (user.id) await supabase.auth.admin.deleteUser(user.id);
    }
  });

  test("signed-in user with a home location set can search by name with geolocation denied and no session cache", async ({
    page,
  }) => {
    await signIn(page, homeUser);
    await page.goto("/search");

    await page.locator("#name").fill(FIXTURE_NAME);
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText(FIXTURE_NAME)).toBeVisible({ timeout: 15_000 });
  });

  test("signed-in user with no home location set still hits the location error", async ({ page }) => {
    await signIn(page, noHomeUser);
    await page.goto("/search");

    await page.locator("#name").fill(FIXTURE_NAME);
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(
      page.getByText("We need a location to search from. Try the home page instead.")
    ).toBeVisible();
    await expect(page.getByText(FIXTURE_NAME)).toHaveCount(0);
  });

  test("signed-out user still hits the location error", async ({ page }) => {
    await page.goto("/search");

    await page.locator("#name").fill(FIXTURE_NAME);
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(
      page.getByText("We need a location to search from. Try the home page instead.")
    ).toBeVisible();
    await expect(page.getByText(FIXTURE_NAME)).toHaveCount(0);
  });
});

test.describe("Discover page is unaffected", () => {
  test("still has location, radius, category, and type controls", async ({ page }) => {
    await page.goto("/discover");

    await expect(page.locator("#location")).toBeVisible();
    await expect(page.locator("#radius")).toBeVisible();
    await expect(page.locator("#category")).toBeVisible();

    for (const label of ["All", "Restaurants", "Bars", "Coffee", "Bakeries", "Breweries"]) {
      await expect(page.getByRole("button", { name: label, exact: true })).toBeVisible();
    }
    await expect(page.getByRole("button", { name: "All", exact: true })).toHaveAttribute(
      "aria-pressed",
      "true"
    );

    await expect(page.locator("#name")).toHaveCount(0);
  });
});
