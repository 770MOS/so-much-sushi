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

// Icon path prefixes - same convention as the manual verification: cheap
// and unambiguous way to identify which of the 5 category icons a marker
// is rendering without parsing full SVG geometry.
const ICON_PREFIX = {
  restaurants: "M19 3v12h-5c-.0",
  bars: "M8 21h8",
  coffee: "M5 11h14v-3h-14",
};

const STARRED_COLOR = "rgb(251, 191, 36)"; // amber-400, #fbbf24
const UNSTARRED_COLOR = "rgb(161, 161, 170)"; // zinc-400, #a1a1aa

const FIXTURE_RESTAURANT = `Playwright Icon Restaurant ${RUN_ID}`;
const FIXTURE_BAR = `Playwright Icon Bar ${RUN_ID}`;
const FIXTURE_COFFEE = `Playwright Icon Coffee ${RUN_ID}`;

const fixtureIds: Record<string, string> = {};
const categoryIds: Record<string, string> = {};

async function createFixtureEntity(name: string, categorySlug: string): Promise<string> {
  const { data, error } = await supabase
    .from("entities")
    .insert({
      name,
      address: "Arlington, VA",
      location: `SRID=4326;POINT(${MOCK_LNG} ${MOCK_LAT})`,
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(`Failed to insert fixture "${name}": ${error?.message}`);

  const { error: linkError } = await supabase
    .from("entity_categories")
    .insert({ entity_id: data.id, category_id: categoryIds[categorySlug] });
  if (linkError) throw new Error(`Failed to tag fixture "${name}": ${linkError.message}`);

  return data.id;
}

type TestUser = { id: string; email: string; handle: string };

const mainUser: TestUser = {
  id: "",
  email: `test+iconmain-${RUN_ID}@example.com`,
  handle: `pw-icon-main-${RUN_ID}`,
};
const friendUser: TestUser = {
  id: "",
  email: `test+iconfriend-${RUN_ID}@example.com`,
  handle: `pw-icon-friend-${RUN_ID}`,
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
  await page.getByRole("button", { name: "Map", exact: true }).click();
}

async function singleMarkerIconInfo(page: Page) {
  await expect(page.locator(".maplibregl-marker")).toHaveCount(1, { timeout: 10_000 });
  return page.evaluate(() => {
    const marker = document.querySelector(".maplibregl-marker")!;
    const path = marker.querySelector("g path");
    const wrapperColor = getComputedStyle(marker).color;
    return { iconPrefix: path ? path.getAttribute("d")!.slice(0, 15) : null, color: wrapperColor };
  });
}

test.use({
  geolocation: { latitude: MOCK_LAT, longitude: MOCK_LNG },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  for (const slug of ["restaurants", "bars", "coffee"]) {
    const { data, error } = await supabase.from("categories").select("id").eq("slug", slug).single();
    if (error || !data) throw new Error(`Could not find "${slug}" category: ${error?.message}`);
    categoryIds[slug] = data.id;
  }

  await Promise.all([createTestUser(mainUser), createTestUser(friendUser)]);

  fixtureIds.restaurant = await createFixtureEntity(FIXTURE_RESTAURANT, "restaurants");
  fixtureIds.bar = await createFixtureEntity(FIXTURE_BAR, "bars");
  fixtureIds.coffee = await createFixtureEntity(FIXTURE_COFFEE, "coffee");

  // mainUser stars the restaurant fixture (Profile Starred map + color test).
  const { error: starError } = await supabase
    .from("stars")
    .insert({ user_id: mainUser.id, entity_id: fixtureIds.restaurant });
  if (starError) throw new Error(`Failed to seed star: ${starError.message}`);

  // friendUser stars the bar fixture, and is an accepted connection of
  // mainUser - shows up on mainUser's Recommended page.
  const { error: friendStarError } = await supabase
    .from("stars")
    .insert({ user_id: friendUser.id, entity_id: fixtureIds.bar });
  if (friendStarError) throw new Error(`Failed to seed friend star: ${friendStarError.message}`);

  const { error: friendshipError } = await supabase.from("friendships").insert({
    requester_id: mainUser.id,
    addressee_id: friendUser.id,
    status: "accepted",
  });
  if (friendshipError) throw new Error(`Failed to create friendship: ${friendshipError.message}`);
});

test.afterAll(async () => {
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", mainUser.id)
    .eq("addressee_id", friendUser.id);
  for (const id of Object.values(fixtureIds)) {
    await supabase.from("entity_categories").delete().eq("entity_id", id);
    await supabase.from("stars").delete().eq("entity_id", id);
    await supabase.from("entities").delete().eq("id", id);
  }
  for (const user of [mainUser, friendUser]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("map tiles load MapTiler's Streets style (streets-v4), not the old Basic style", async ({ page }) => {
  const tileStyleRequests: string[] = [];
  page.on("request", (req) => {
    if (req.url().includes("api.maptiler.com/maps/")) tileStyleRequests.push(req.url());
  });

  await searchByName(page, FIXTURE_RESTAURANT);
  await expect.poll(() => tileStyleRequests.length).toBeGreaterThan(0);

  expect(tileStyleRequests.some((u) => u.includes("/maps/streets-v4/"))).toBe(true);
  expect(tileStyleRequests.some((u) => u.includes("/maps/basic-v2/"))).toBe(false);
});

test("search Map view: restaurant, bar, and coffee shop each render a distinct icon", async ({
  page,
}) => {
  await searchByName(page, FIXTURE_RESTAURANT);
  const restaurantIcon = await singleMarkerIconInfo(page);
  expect(restaurantIcon.iconPrefix).toBe(ICON_PREFIX.restaurants);

  await searchByName(page, FIXTURE_BAR);
  const barIcon = await singleMarkerIconInfo(page);
  expect(barIcon.iconPrefix).toBe(ICON_PREFIX.bars);

  await searchByName(page, FIXTURE_COFFEE);
  const coffeeIcon = await singleMarkerIconInfo(page);
  expect(coffeeIcon.iconPrefix).toBe(ICON_PREFIX.coffee);

  // Pairwise distinct, not just individually matching expectations.
  const prefixes = [restaurantIcon.iconPrefix, barIcon.iconPrefix, coffeeIcon.iconPrefix];
  expect(new Set(prefixes).size).toBe(3);
});

test("color still means personal status, independent of the icon: default vs starred", async ({
  page,
}) => {
  await signIn(page, mainUser);
  await searchByName(page, FIXTURE_COFFEE);
  const before = await singleMarkerIconInfo(page);
  expect(before.iconPrefix).toBe(ICON_PREFIX.coffee);
  expect(before.color).toBe(UNSTARRED_COLOR);

  await page.locator(".maplibregl-marker").click();
  await page.locator(".maplibregl-popup").getByRole("button", { name: "Star this place" }).click();
  await expect(
    page.locator(".maplibregl-popup").getByRole("button", { name: "Unstar this place" })
  ).toBeVisible({ timeout: 10_000 });

  const after = await singleMarkerIconInfo(page);
  // Same icon (category never changed) - only the color did.
  expect(after.iconPrefix).toBe(ICON_PREFIX.coffee);
  expect(after.color).toBe(STARRED_COLOR);

  // Cleanup - this fixture is otherwise unstarred by any user in afterAll.
  await supabase.from("stars").delete().eq("entity_id", fixtureIds.coffee);
});

test("consistent icon across all 4 EntityMap consumers: search, Profile Starred, Recommended, venue page", async ({
  page,
}) => {
  // 1. Search Map view (already covered in detail above; quick recheck here
  // for the specific "all 4 consumers" framing).
  await searchByName(page, FIXTURE_RESTAURANT);
  expect((await singleMarkerIconInfo(page)).iconPrefix).toBe(ICON_PREFIX.restaurants);

  // 2. Profile Starred map - mainUser has the restaurant fixture starred.
  await signIn(page, mainUser);
  await page.goto("/profile");
  await expect(page.getByText(FIXTURE_RESTAURANT)).toBeVisible({ timeout: 15_000 });
  expect((await singleMarkerIconInfo(page)).iconPrefix).toBe(ICON_PREFIX.restaurants);

  // 3. Recommended - friendUser starred the bar fixture, mainUser is
  // friends with them.
  await page.goto("/recommended");
  await expect(page.getByText(FIXTURE_BAR)).toBeVisible({ timeout: 15_000 });
  await page.getByRole("button", { name: "Map", exact: true }).click();
  expect((await singleMarkerIconInfo(page)).iconPrefix).toBe(ICON_PREFIX.bars);

  // 4. Venue page's single-pin map.
  await page.goto(`/venue/${fixtureIds.coffee}`);
  expect((await singleMarkerIconInfo(page)).iconPrefix).toBe(ICON_PREFIX.coffee);
});
