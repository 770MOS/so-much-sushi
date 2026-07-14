import { test, expect } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// Arlington, VA - matches the seed data and the mocked geolocation used
// elsewhere in this repo's e2e specs.
const MOCK_LAT = 38.8816;
const MOCK_LNG = -77.091;

// ~40 miles from Arlington (Baltimore, MD) - definitively outside the home
// page's reused 25-mile-max radius slider when searched from Arlington,
// but findable when the location field is set to Baltimore itself with
// the slider maxed out.
const FAR_LAT = 39.2904;
const FAR_LNG = -76.6122;
const FAR_LOCATION_QUERY = "Baltimore, MD";

const NAME_FIXTURE = "Playwright Test Home Combined Name Target";
const LOCATION_FIXTURE = "Playwright Test Home Combined Location Target";

let nameFixtureId: string;
let locationFixtureId: string;

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
  if (catError || !category) {
    throw new Error(`Could not find "restaurants" category: ${catError?.message}`);
  }

  // Near the mocked location, unique name - proves a name-only query works.
  const { data: nameFixture, error: nameError } = await supabase
    .from("entities")
    .insert({
      name: NAME_FIXTURE,
      address: "Arlington, VA",
      location: `SRID=4326;POINT(${MOCK_LNG} ${MOCK_LAT})`,
    })
    .select("id")
    .single();
  if (nameError || !nameFixture) {
    throw new Error(`Failed to insert name fixture: ${nameError?.message}`);
  }
  nameFixtureId = nameFixture.id;

  // Far away, distinct name - proves a location-only query reaches out to
  // wherever the typed/geocoded location resolves to, not just nearby data.
  const { data: locationFixture, error: locationError } = await supabase
    .from("entities")
    .insert({
      name: LOCATION_FIXTURE,
      address: "Boston, MA",
      location: `SRID=4326;POINT(${FAR_LNG} ${FAR_LAT})`,
    })
    .select("id")
    .single();
  if (locationError || !locationFixture) {
    throw new Error(`Failed to insert location fixture: ${locationError?.message}`);
  }
  locationFixtureId = locationFixture.id;

  const { error: linkError } = await supabase.from("entity_categories").insert([
    { entity_id: nameFixtureId, category_id: category.id },
    { entity_id: locationFixtureId, category_id: category.id },
  ]);
  if (linkError) {
    throw new Error(`Failed to tag fixtures: ${linkError.message}`);
  }
});

test.afterAll(async () => {
  const ids = [nameFixtureId, locationFixtureId].filter(Boolean);
  if (ids.length === 0) return;
  await supabase.from("entity_categories").delete().in("entity_id", ids);
  await supabase.from("entities").delete().in("id", ids);
});

test.describe("sidebar", () => {
  test("all six destinations are present with the right hrefs", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto("/");

    const nav = page.locator('nav[aria-label="Main"]:visible');

    const destinations: [string, string][] = [
      ["Search", "/search"],
      ["Discover", "/discover"],
      ["Starred", "/starred"],
      ["Lists", "/profile?tab=lists"],
      ["Recommended", "/recommended"],
      ["Connections", "/connections"],
    ];

    for (const [label, href] of destinations) {
      const link = nav.getByRole("link", { name: label });
      await expect(link).toBeVisible();
      await expect(link).toHaveAttribute("href", href);
    }
  });

  test("Search and Discover (unauthenticated-accessible) actually navigate", async ({ page }) => {
    await page.goto("/");
    const nav = page.locator('nav[aria-label="Main"]:visible');

    await nav.getByRole("link", { name: "Discover" }).click();
    await expect(page).toHaveURL(/\/discover$/);

    await nav.getByRole("link", { name: "Search" }).click();
    await expect(page).toHaveURL(/\/search$/);
  });
});

test.describe("/discover - unchanged experience", () => {
  test("has the full original form: location, radius, type row, and category tree dropdown", async ({
    page,
  }) => {
    await page.goto("/discover");

    await expect(page.locator("#location")).toBeVisible();
    await expect(page.locator("#radius")).toBeVisible();
    await expect(page.locator("#category")).toBeVisible();

    for (const label of ["All", "Restaurants", "Bars", "Coffee", "Bakeries", "Breweries"]) {
      await expect(page.getByRole("button", { name: label, exact: true })).toBeVisible();
    }

    // No name field on Discover - that's exclusive to the new home page.
    await expect(page.locator("#name")).toHaveCount(0);
  });

  test("category dropdown still hides for Bars/Coffee/Bakeries/Breweries", async ({ page }) => {
    await page.goto("/discover");

    await page.getByRole("button", { name: "Bars", exact: true }).click();
    await expect(page.locator("#category")).toHaveCount(0);
  });
});

test.describe("home page (/) - combined quick search", () => {
  test("has name, location, radius, and the simple type row - no deep category tree", async ({
    page,
  }) => {
    await page.goto("/");

    await expect(page.locator("#name")).toBeVisible();
    await expect(page.locator("#location")).toBeVisible();
    await expect(page.locator("#radius")).toBeVisible();

    for (const label of ["All", "Restaurants", "Bars", "Coffee", "Bakeries", "Breweries"]) {
      await expect(page.getByRole("button", { name: label, exact: true })).toBeVisible();
    }

    // The deep cuisine tree (category select) is Discover-only.
    await expect(page.locator("#category")).toHaveCount(0);
  });

  test("selecting a type does not auto-run search - only the Search button does", async ({
    page,
  }) => {
    await page.goto("/");

    const searchRequests: string[] = [];
    page.on("request", (req) => {
      if (req.url().includes("/rest/v1/rpc/search_entities")) searchRequests.push(req.url());
    });

    await page.getByRole("button", { name: "Bars", exact: true }).click();
    await page.waitForTimeout(500);
    expect(searchRequests).toHaveLength(0);
  });

  test("name-only query finds a place by name near the current location", async ({ page }) => {
    await page.goto("/");

    await page.locator("#name").fill(NAME_FIXTURE);
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText(NAME_FIXTURE)).toBeVisible();
    await expect(page.getByText(LOCATION_FIXTURE)).toHaveCount(0);
  });

  test("location-only query finds places at the typed location, name field empty", async ({
    page,
  }) => {
    await page.goto("/");

    await page.locator("#location").fill(FAR_LOCATION_QUERY);
    // #radius is a native range input - drive it with the keyboard (max
    // it out via End), not .fill(), which doesn't work on range inputs.
    await page.locator("#radius").press("End");
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText(LOCATION_FIXTURE)).toBeVisible({ timeout: 15_000 });
  });

  test("combined name + location query applies both filters together (AND)", async ({ page }) => {
    await page.goto("/");

    // Right name, wrong (far) location, radius maxed at 25mi - AND
    // semantics mean this should find nothing, proving both filters are
    // applied together rather than either alone.
    await page.locator("#name").fill(NAME_FIXTURE);
    await page.locator("#location").fill(FAR_LOCATION_QUERY);
    await page.locator("#radius").press("End");
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText("No restaurants found nearby")).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(NAME_FIXTURE)).toHaveCount(0);

    // Right name, right (matching) location - AND semantics mean this
    // should find it.
    await page.locator("#name").fill(NAME_FIXTURE);
    await page.locator("#location").fill("Arlington, VA");
    await page.getByRole("button", { name: "Search", exact: true }).click();

    await expect(page.getByText(NAME_FIXTURE)).toBeVisible({ timeout: 15_000 });
  });
});
