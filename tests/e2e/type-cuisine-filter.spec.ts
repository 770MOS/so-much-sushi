import { test, expect } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

// Null Island - no real entity data exists here, so a search at this exact
// point only ever surfaces the fixtures this suite creates and cleans up.
const FIXTURE_LAT = 0;
const FIXTURE_LNG = 0;

let cocktailBarEntityId: string;
let wineBarEntityId: string;

test.use({
  geolocation: { latitude: FIXTURE_LAT, longitude: FIXTURE_LNG },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  const { data: categoryRows, error: catError } = await supabase
    .from("categories")
    .select("id, slug")
    .in("slug", ["cocktail_bar", "wine_bar"]);
  if (catError || !categoryRows || categoryRows.length !== 2) {
    throw new Error(
      `Expected to find cocktail_bar and wine_bar categories, got: ${JSON.stringify(categoryRows)} (${catError?.message})`
    );
  }
  const categoryIdBySlug = new Map(categoryRows.map((c) => [c.slug, c.id]));

  const { data: cocktailBar, error: cocktailError } = await supabase
    .from("entities")
    .insert({
      name: "Playwright Test Cocktail Bar",
      address: "Null Island",
      location: `SRID=4326;POINT(${FIXTURE_LNG} ${FIXTURE_LAT})`,
    })
    .select("id")
    .single();
  if (cocktailError || !cocktailBar) {
    throw new Error(`Failed to insert cocktail bar fixture: ${cocktailError?.message}`);
  }
  cocktailBarEntityId = cocktailBar.id;

  const { data: wineBar, error: wineError } = await supabase
    .from("entities")
    .insert({
      name: "Playwright Test Wine Bar",
      address: "Null Island",
      location: `SRID=4326;POINT(${FIXTURE_LNG} ${FIXTURE_LAT})`,
    })
    .select("id")
    .single();
  if (wineError || !wineBar) {
    throw new Error(`Failed to insert wine bar fixture: ${wineError?.message}`);
  }
  wineBarEntityId = wineBar.id;

  const { error: linkError } = await supabase.from("entity_categories").insert([
    { entity_id: cocktailBarEntityId, category_id: categoryIdBySlug.get("cocktail_bar") },
    { entity_id: wineBarEntityId, category_id: categoryIdBySlug.get("wine_bar") },
  ]);
  if (linkError) {
    throw new Error(`Failed to tag fixtures with their categories: ${linkError.message}`);
  }
});

test.afterAll(async () => {
  const ids = [cocktailBarEntityId, wineBarEntityId].filter(Boolean);
  if (ids.length === 0) return;
  await supabase.from("entity_categories").delete().in("entity_id", ids);
  await supabase.from("entities").delete().in("id", ids);
});

test("All and Restaurants show the category dropdown", async ({ page }) => {
  await page.goto("/");

  // "All" is the default type on load.
  await expect(page.locator("#category")).toBeVisible();

  await page.getByRole("button", { name: "Restaurants", exact: true }).click();
  await expect(page.locator("#category")).toBeVisible();
});

test("Bars, Coffee, Bakeries, and Breweries hide the category dropdown", async ({ page }) => {
  await page.goto("/");

  for (const label of ["Bars", "Coffee", "Bakeries", "Breweries"]) {
    await page.getByRole("button", { name: label, exact: true }).click();
    await expect(page.locator("#category")).toHaveCount(0);
  }
});

test("selecting a type does not auto-run search - only the Search button does", async ({ page }) => {
  await page.goto("/");

  const searchRequests: string[] = [];
  page.on("request", (req) => {
    if (req.url().includes("/rest/v1/rpc/search_entities")) {
      searchRequests.push(req.url());
    }
  });

  await page.getByRole("button", { name: "Bars", exact: true }).click();
  await page.waitForTimeout(500);
  expect(searchRequests).toHaveLength(0);

  await page.locator("#location").fill("22201");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect.poll(() => searchRequests.length, { timeout: 15_000 }).toBeGreaterThan(0);
});

test("a Bars search returns Cocktail Bar and Wine Bar tagged places with no sub-selection", async ({
  page,
}) => {
  // Best-effort reverse-geocode label lookup - block it so the location
  // field deterministically stays "Current location" (avoids a race where
  // it gets renamed before the second, explicit Search click).
  await page.route("**/nominatim.openstreetmap.org/reverse**", (route) => route.abort());

  await page.goto("/");

  await page.getByRole("button", { name: "Use my location" }).click();
  await expect(page.locator("#location")).toHaveValue("Current location");
  await page.waitForTimeout(1000);

  await page.getByRole("button", { name: "Bars", exact: true }).click();
  await expect(page.locator("#category")).toHaveCount(0);

  await page.getByRole("button", { name: "Search", exact: true }).click();

  await expect(page.getByText("Playwright Test Cocktail Bar")).toBeVisible();
  await expect(page.getByText("Playwright Test Wine Bar")).toBeVisible();
  await expect(page.getByText("Cocktail Bar", { exact: false }).first()).toBeVisible();
  await expect(page.getByText("Wine Bar", { exact: false }).first()).toBeVisible();
});
