import { test, expect, type Page } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

const PASSWORD = "TestPassword123!";
const RUN_ID = Date.now().toString(36);

// Mocked "current location" for these tests - Arlington, VA, matching the
// rest of the seed data and other e2e specs in this repo.
const MOCK_LAT = 38.8769326;
const MOCK_LNG = -77.0893094;

type TestUser = { id: string; email: string; handle: string };

const starUser: TestUser = {
  id: "",
  email: `test+mapstar-${RUN_ID}@example.com`,
  handle: `pw-map-star-${RUN_ID}`,
};
const friendUser: TestUser = {
  id: "",
  email: `test+mapfriend-${RUN_ID}@example.com`,
  handle: `pw-map-friend-${RUN_ID}`,
};

const FIXTURE_SEARCH = `Playwright Map Popup Search Target ${RUN_ID}`;
const FIXTURE_SIGNED_OUT = `Playwright Map Popup Signed Out Target ${RUN_ID}`;
const FIXTURE_PROFILE_STARRED = `Playwright Map Popup Profile Starred Target ${RUN_ID}`;
const FIXTURE_RECOMMENDED = `Playwright Map Popup Recommended Target ${RUN_ID}`;

const fixtureIds: Record<string, string> = {};

async function createFixtureEntity(name: string): Promise<string> {
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
      name,
      address: "Arlington, VA",
      location: `SRID=4326;POINT(${MOCK_LNG} ${MOCK_LAT})`,
    })
    .select("id")
    .single();
  if (error || !data) throw new Error(`Failed to insert fixture "${name}": ${error?.message}`);

  const { error: linkError } = await supabase
    .from("entity_categories")
    .insert({ entity_id: data.id, category_id: category.id });
  if (linkError) throw new Error(`Failed to tag fixture "${name}": ${linkError.message}`);

  return data.id;
}

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

  // First sign-in for a user with no home location set shows a full-screen
  // "Set your home location?" prompt that intercepts every subsequent click.
  // Its dismissal is only remembered client-side (localStorage), and
  // Playwright gives each test a fresh browser context, so it reappears on
  // every test that signs in as one of these (deliberately homeless) test
  // users - dismiss it here rather than in each test. It shows up after an
  // async get_my_home_location round trip, not immediately on navigation,
  // so this needs a real wait rather than a quick best-effort check.
  const skipButton = page.getByRole("button", { name: "Skip for now" });
  await expect(skipButton).toBeVisible({ timeout: 10_000 });
  await skipButton.click();
  await expect(page.getByText("Set your home location?")).toHaveCount(0);
}

async function isStarredInDb(userId: string, entityId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("stars")
    .select("entity_id")
    .eq("user_id", userId)
    .eq("entity_id", entityId);
  if (error) throw new Error(`Failed to check stars: ${error.message}`);
  return (data ?? []).length > 0;
}

test.use({
  geolocation: { latitude: MOCK_LAT, longitude: MOCK_LNG },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  await Promise.all([createTestUser(starUser), createTestUser(friendUser)]);

  fixtureIds.search = await createFixtureEntity(FIXTURE_SEARCH);
  fixtureIds.signedOut = await createFixtureEntity(FIXTURE_SIGNED_OUT);
  fixtureIds.profileStarred = await createFixtureEntity(FIXTURE_PROFILE_STARRED);
  fixtureIds.recommended = await createFixtureEntity(FIXTURE_RECOMMENDED);

  // starUser already has this one starred - profile Starred map test unstars it.
  const { error: starError } = await supabase
    .from("stars")
    .insert({ user_id: starUser.id, entity_id: fixtureIds.profileStarred });
  if (starError) throw new Error(`Failed to seed starred fixture: ${starError.message}`);

  // friendUser starred the "recommended" fixture, and is an accepted
  // connection of starUser - so it shows up on starUser's Recommended page,
  // without starUser having personally starred it (yet).
  const { error: friendStarError } = await supabase
    .from("stars")
    .insert({ user_id: friendUser.id, entity_id: fixtureIds.recommended });
  if (friendStarError) throw new Error(`Failed to seed friend's star: ${friendStarError.message}`);

  const { error: friendshipError } = await supabase.from("friendships").insert({
    requester_id: starUser.id,
    addressee_id: friendUser.id,
    status: "accepted",
  });
  if (friendshipError) throw new Error(`Failed to create friendship: ${friendshipError.message}`);
});

test.afterAll(async () => {
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", starUser.id)
    .eq("addressee_id", friendUser.id);
  for (const id of Object.values(fixtureIds)) {
    await supabase.from("entity_categories").delete().eq("entity_id", id);
    await supabase.from("stars").delete().eq("entity_id", id);
    await supabase.from("entities").delete().eq("id", id);
  }
  for (const user of [starUser, friendUser]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("search page: starring and unstarring from the map popup persists", async ({ page }) => {
  await signIn(page, starUser);
  await page.goto("/search");

  await page.locator("#name").fill(FIXTURE_SEARCH);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText(FIXTURE_SEARCH)).toBeVisible({ timeout: 15_000 });

  await page.getByRole("button", { name: "Map", exact: true }).click();
  await page.locator(".maplibregl-marker").click();

  const popup = page.locator(".maplibregl-popup");
  await expect(popup.getByText(FIXTURE_SEARCH)).toBeVisible();

  const starButton = popup.getByRole("button", { name: "Star this place" });
  await expect(starButton).toBeVisible();

  await starButton.click();
  await expect(popup.getByRole("button", { name: "Unstar this place" })).toBeVisible({
    timeout: 10_000,
  });
  await expect
    .poll(() => isStarredInDb(starUser.id, fixtureIds.search), { timeout: 10_000 })
    .toBe(true);

  // Persists across a reload, not just in local component state.
  await page.reload();
  await page.locator("#name").fill(FIXTURE_SEARCH);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText(FIXTURE_SEARCH)).toBeVisible({ timeout: 15_000 });
  await page.getByRole("button", { name: "Map", exact: true }).click();
  await page.locator(".maplibregl-marker").click();
  await expect(
    page.locator(".maplibregl-popup").getByRole("button", { name: "Unstar this place" })
  ).toBeVisible();

  // Unstar it back, confirm that also persists.
  await page.locator(".maplibregl-popup").getByRole("button", { name: "Unstar this place" }).click();
  await expect(
    page.locator(".maplibregl-popup").getByRole("button", { name: "Star this place" })
  ).toBeVisible({ timeout: 10_000 });
  await expect
    .poll(() => isStarredInDb(starUser.id, fixtureIds.search), { timeout: 10_000 })
    .toBe(false);
});

test("search page: clicking the popup star while signed out prompts sign-in instead of failing silently", async ({
  page,
}) => {
  await page.goto("/search");

  await page.locator("#name").fill(FIXTURE_SIGNED_OUT);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText(FIXTURE_SIGNED_OUT)).toBeVisible({ timeout: 15_000 });

  await page.getByRole("button", { name: "Map", exact: true }).click();
  await page.locator(".maplibregl-marker").click();

  const popup = page.locator(".maplibregl-popup");
  await popup.getByRole("button", { name: "Star this place" }).click();

  await page.waitForURL("/sign-in", { timeout: 10_000 });

  // And no star was actually recorded server-side.
  expect(await isStarredInDb(starUser.id, fixtureIds.signedOut)).toBe(false);
});

test("profile Starred map: unstarring from the popup removes it after reload", async ({ page }) => {
  await signIn(page, starUser);
  await page.goto("/profile");

  await expect(page.getByText(FIXTURE_PROFILE_STARRED)).toBeVisible({ timeout: 15_000 });
  await page.locator(".maplibregl-marker").first().click();

  const popup = page.locator(".maplibregl-popup");
  await expect(popup.getByText(FIXTURE_PROFILE_STARRED)).toBeVisible();
  await expect(popup.getByRole("button", { name: "Unstar this place" })).toBeVisible();

  await popup.getByRole("button", { name: "Unstar this place" }).click();
  await expect(popup.getByRole("button", { name: "Star this place" })).toBeVisible({
    timeout: 10_000,
  });
  await expect
    .poll(() => isStarredInDb(starUser.id, fixtureIds.profileStarred), { timeout: 10_000 })
    .toBe(false);

  // The Starred map's dataset is "currently starred by me" - after a reload
  // this entity should no longer be part of it at all.
  await page.reload();
  await expect(page.getByText(FIXTURE_PROFILE_STARRED)).toHaveCount(0, { timeout: 15_000 });
});

test("Recommended map: starring a friend-recommended place from the popup persists", async ({
  page,
}) => {
  await signIn(page, starUser);
  await page.goto("/recommended");

  await expect(page.getByText(FIXTURE_RECOMMENDED)).toBeVisible({ timeout: 15_000 });
  await page.getByRole("button", { name: "Map", exact: true }).click();
  await page.locator(".maplibregl-marker").click();

  const popup = page.locator(".maplibregl-popup");
  await expect(popup.getByText(FIXTURE_RECOMMENDED)).toBeVisible();
  // starUser hasn't personally starred this yet - only friendUser has.
  await expect(popup.getByRole("button", { name: "Star this place" })).toBeVisible();

  await popup.getByRole("button", { name: "Star this place" }).click();
  await expect(popup.getByRole("button", { name: "Unstar this place" })).toBeVisible({
    timeout: 10_000,
  });
  await expect
    .poll(() => isStarredInDb(starUser.id, fixtureIds.recommended), { timeout: 10_000 })
    .toBe(true);

  await page.reload();
  await expect(page.getByText(FIXTURE_RECOMMENDED)).toBeVisible({ timeout: 15_000 });
  await page.getByRole("button", { name: "Map", exact: true }).click();
  await page.locator(".maplibregl-marker").click();
  await expect(
    page.locator(".maplibregl-popup").getByRole("button", { name: "Unstar this place" })
  ).toBeVisible();
});
