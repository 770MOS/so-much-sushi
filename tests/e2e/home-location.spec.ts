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

type TestUser = { id: string; email: string; handle: string };

const promptUser: TestUser = { id: "", email: `test+hlprompt-${RUN_ID}@example.com`, handle: `pw-hl-prompt-${RUN_ID}` };
const skipUser: TestUser = { id: "", email: `test+hlskip-${RUN_ID}@example.com`, handle: `pw-hl-skip-${RUN_ID}` };
const settingsUser: TestUser = { id: "", email: `test+hlsettings-${RUN_ID}@example.com`, handle: `pw-hl-settings-${RUN_ID}` };
const prefillUser: TestUser = { id: "", email: `test+hlprefill-${RUN_ID}@example.com`, handle: `pw-hl-prefill-${RUN_ID}` };
const privacyOwner: TestUser = { id: "", email: `test+hlprivowner-${RUN_ID}@example.com`, handle: `pw-hl-privowner-${RUN_ID}` };
const privacyStranger: TestUser = { id: "", email: `test+hlprivstranger-${RUN_ID}@example.com`, handle: `pw-hl-privstranger-${RUN_ID}` };
const privacyFriend: TestUser = { id: "", email: `test+hlprivfriend-${RUN_ID}@example.com`, handle: `pw-hl-privfriend-${RUN_ID}` };

const ALL_USERS = [promptUser, skipUser, settingsUser, prefillUser, privacyOwner, privacyStranger, privacyFriend];

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

test.use({
  geolocation: { latitude: 38.8816, longitude: -77.091 },
  permissions: ["geolocation"],
});

test.beforeAll(async () => {
  await Promise.all(ALL_USERS.map((u) => createTestUser(u)));

  await supabase
    .from("profiles")
    .update({ home_city: "Rockville", home_state: "MD" })
    .eq("id", settingsUser.id);
  await supabase
    .from("profiles")
    .update({ home_city: "Boston", home_state: "MA" })
    .eq("id", prefillUser.id);
  await supabase
    .from("profiles")
    .update({ home_city: "Seattle", home_state: "WA" })
    .eq("id", privacyOwner.id);

  const { error: friendError } = await supabase.from("friendships").insert({
    requester_id: privacyOwner.id,
    addressee_id: privacyFriend.id,
    status: "accepted",
  });
  if (friendError) throw new Error(`Failed to create friendship: ${friendError.message}`);
});

test.afterAll(async () => {
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", privacyOwner.id)
    .eq("addressee_id", privacyFriend.id);
  for (const user of ALL_USERS) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("prompt appears on first sign-in when home location is unset, and granting it saves directly to the profile", async ({
  page,
}) => {
  await signIn(page, promptUser);

  await expect(page.getByText("Set your home location?")).toBeVisible();

  await page.getByRole("button", { name: "Use my current location" }).click();
  await expect(page.getByText("Set your home location?")).toHaveCount(0, { timeout: 10_000 });

  await page.goto("/profile");
  await expect(page.getByText("Home location:")).toBeVisible();
  await expect(page.getByText("Arlington, VA")).toBeVisible();
});

test("prompt does not reappear on a subsequent sign-in once set", async ({ page }) => {
  // Fresh context/page (Playwright isolates per test) - no localStorage
  // dismissal carried over, so this only passes if the DB-backed check
  // (home_city is now non-null, from the previous test) is what's really
  // suppressing it, not a stale client-side flag.
  await signIn(page, promptUser);
  await expect(page.getByText("Set your home location?")).toHaveCount(0);
});

test("skipping the prompt suppresses it on this device even though home location stays unset", async ({
  page,
}) => {
  await signIn(page, skipUser);
  await expect(page.getByText("Set your home location?")).toBeVisible();

  await page.getByRole("button", { name: "Skip for now" }).click();
  await expect(page.getByText("Set your home location?")).toHaveCount(0);

  await page.reload();
  await expect(page.getByText("Set your home location?")).toHaveCount(0);

  await page.goto("/profile");
  await expect(page.getByText("Not set")).toBeVisible();
});

test("Account Settings shows the set home location, with a working Change flow for ZIP, city name, and geolocation", async ({
  page,
}) => {
  await signIn(page, settingsUser);
  await page.goto("/profile");

  await expect(page.getByText("Home location:")).toBeVisible();
  await expect(page.getByText("Rockville, MD")).toBeVisible();

  // Change via ZIP code.
  await page.getByRole("button", { name: "Change" }).click();
  await expect(page.locator("#home-location")).toHaveValue("Rockville, MD");
  await page.locator("#home-location").fill("10001");
  await page.getByRole("button", { name: "Save", exact: true }).last().click();
  await expect(page.getByText("New York, NY")).toBeVisible({ timeout: 15_000 });

  // Change via a plain city name.
  await page.getByRole("button", { name: "Change" }).click();
  await page.locator("#home-location").fill("Chicago, IL");
  await page.getByRole("button", { name: "Save", exact: true }).last().click();
  await expect(page.getByText("Chicago, IL")).toBeVisible({ timeout: 15_000 });

  // Change via the geolocation button (mocked to Arlington, VA).
  await page.getByRole("button", { name: "Change" }).click();
  await page.getByRole("button", { name: "Use my location" }).click();
  await expect(page.locator("#home-location")).toHaveValue("Current location");
  await page.getByRole("button", { name: "Save", exact: true }).last().click();
  await expect(page.getByText("Arlington, VA")).toBeVisible({ timeout: 15_000 });

  // Deletable.
  await page.getByRole("button", { name: "Clear" }).click();
  await expect(page.getByText("Not set")).toBeVisible();
});

test("home page pre-fills the location field from a set home location, and remains editable", async ({
  page,
}) => {
  await signIn(page, prefillUser);
  await page.goto("/");

  await expect(page.locator("#location")).toHaveValue("Boston, MA");

  // Still just a starting value - editable/overridable, not locked in.
  await page.locator("#location").fill("Chicago, IL");
  await expect(page.locator("#location")).toHaveValue("Chicago, IL");
});

test("home location never appears on the public /u/[handle] profile page", async ({ page, browser }) => {
  // Stranger (signed in, no connection).
  await signIn(page, privacyStranger);
  await page.goto(`/u/${privacyOwner.handle}`);
  let body = await page.textContent("body");
  expect(body).not.toContain("Seattle");
  expect(body).not.toContain("Home location");

  // Accepted friend - the boundary holds even for connections.
  const friendPage = await (await browser.newContext()).newPage();
  await signIn(friendPage, privacyFriend);
  await friendPage.goto(`/u/${privacyOwner.handle}`);
  body = await friendPage.textContent("body");
  expect(body).not.toContain("Seattle");
  expect(body).not.toContain("Home location");

  // Fully unauthenticated visitor.
  const anonPage = await (await browser.newContext()).newPage();
  await anonPage.goto(`/u/${privacyOwner.handle}`);
  body = await anonPage.textContent("body");
  expect(body).not.toContain("Seattle");
  expect(body).not.toContain("Home location");
});
