import { test, expect, type Page } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

const PASSWORD = "TestPassword123!";
const RUN_ID = Date.now().toString(36).slice(-6);

type TestUser = { id: string; email: string; handle: string };

const owner: TestUser = { id: "", email: `test+listso${RUN_ID}@example.com`, handle: `pwlists_o_${RUN_ID}` };
const friend: TestUser = { id: "", email: `test+listsf${RUN_ID}@example.com`, handle: `pwlists_f_${RUN_ID}` };
const stranger: TestUser = { id: "", email: `test+listss${RUN_ID}@example.com`, handle: `pwlists_s_${RUN_ID}` };

let privateListId: string;
let friendsListId: string;
let publicListId: string;

async function createTestUser(user: TestUser, displayName: string) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: user.email,
    password: PASSWORD,
    email_confirm: true,
  });
  if (error || !data.user) throw new Error(`Failed to create ${user.email}: ${error?.message}`);
  user.id = data.user.id;

  const { error: profileError } = await supabase
    .from("profiles")
    // home_city/home_state set so the unrelated first-sign-in home
    // location prompt never appears and intercepts clicks.
    .update({ handle: user.handle, display_name: displayName, home_city: "Testville", home_state: "TS" })
    .eq("id", user.id);
  if (profileError) throw new Error(`Failed to set profile for ${user.email}: ${profileError.message}`);
}

function getSection(page: Page, heading: string) {
  return page.locator("section").filter({ has: page.getByRole("heading", { name: heading, exact: true }) });
}

async function signIn(page: Page, user: TestUser) {
  await page.goto("/sign-in");
  await page.locator("#email").fill(user.email);
  await page.locator("#password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await page.waitForURL("/", { timeout: 15_000 });
}

test.beforeAll(async () => {
  await createTestUser(owner, "Lists Owner");
  await createTestUser(friend, "Lists Friend");
  await createTestUser(stranger, "Lists Stranger");

  const { error: friendErr } = await supabase
    .from("friendships")
    .insert({ requester_id: owner.id, addressee_id: friend.id, status: "accepted" });
  if (friendErr) throw new Error(`Failed to create friendship: ${friendErr.message}`);

  const { data: priv } = await supabase
    .from("lists")
    .insert({ owner_id: owner.id, name: "PW Private List", visibility: "private" })
    .select("id")
    .single();
  privateListId = priv!.id;

  const { data: fr } = await supabase
    .from("lists")
    .insert({ owner_id: owner.id, name: "PW Friends List", visibility: "friends" })
    .select("id")
    .single();
  friendsListId = fr!.id;

  const { data: pub } = await supabase
    .from("lists")
    .insert({ owner_id: owner.id, name: "PW Public List", visibility: "public" })
    .select("id")
    .single();
  publicListId = pub!.id;
});

test.afterAll(async () => {
  await supabase.from("saved_lists").delete().in("list_id", [privateListId, friendsListId, publicListId]);
  await supabase.from("lists").delete().in("id", [privateListId, friendsListId, publicListId]);
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", owner.id)
    .eq("addressee_id", friend.id);
  for (const user of [owner, friend, stranger]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("sidebar Lists link navigates to the dedicated /lists route", async ({ page }) => {
  await signIn(page, friend);
  await page.locator('nav[aria-label="Main"]:visible').getByRole("link", { name: "Lists" }).click();
  await expect(page).toHaveURL(/\/lists$/);
  await expect(page.locator("h1").getByText("Lists")).toBeVisible();
});

test("/profile no longer shows a Lists tab", async ({ page }) => {
  await signIn(page, friend);
  await page.goto("/profile");

  await expect(page.getByRole("button", { name: "Lists", exact: true })).toHaveCount(0);
  await expect(page.getByText("My Lists")).toHaveCount(0);
});

test("an accepted connection sees the friends list under Shared with me, not the private one", async ({
  page,
}) => {
  await signIn(page, friend);
  await page.goto("/lists");

  await expect(page.getByText("PW Friends List")).toBeVisible();
  await expect(page.getByText("PW Private List")).toHaveCount(0);
});

test("an unconnected stranger sees nothing shared from the owner", async ({ page }) => {
  await signIn(page, stranger);
  await page.goto("/lists");

  await expect(page.getByText("No lists have been shared with you yet.")).toBeVisible();
  await expect(page.getByText("PW Friends List")).toHaveCount(0);
  await expect(page.getByText("PW Private List")).toHaveCount(0);
});

test("saving a list from Shared with me moves it into Saved, with the owner's name shown", async ({
  page,
}) => {
  await signIn(page, friend);
  await page.goto("/lists");

  await expect(page.getByText("You haven't saved any lists yet.")).toBeVisible();

  const sharedSection = getSection(page, "Shared with me");
  await sharedSection.getByRole("button", { name: "Save", exact: true }).click();
  await expect(sharedSection.getByRole("button", { name: "Saved", exact: true })).toBeVisible();

  await page.reload();
  const savedSection = getSection(page, "Saved");
  await expect(savedSection.getByText("PW Friends List")).toBeVisible();
  await expect(savedSection.getByText("Lists Owner")).toBeVisible();

  // The same list's button in "Shared with me" should now also read
  // "Saved" - it's the same underlying save, not a contradiction.
  await expect(getSection(page, "Shared with me").getByRole("button", { name: "Saved", exact: true })).toBeVisible();
});

test("unsaving removes the list from Saved", async ({ page }) => {
  await signIn(page, friend);
  await page.goto("/lists");

  const savedSection = getSection(page, "Saved");
  await expect(savedSection.getByText("PW Friends List")).toBeVisible();
  await savedSection.getByRole("button", { name: "Saved", exact: true }).click();

  await expect(page.getByText("You haven't saved any lists yet.")).toBeVisible();
});

test("saving works directly from the list detail page and from /u/[handle]", async ({ page }) => {
  await signIn(page, friend);

  await page.goto(`/lists/${publicListId}`);
  await expect(page.getByRole("button", { name: "Save", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("button", { name: "Saved", exact: true })).toBeVisible();

  await page.goto(`/u/${owner.handle}`);
  await expect(page.getByText("PW Public List")).toBeVisible();
  await expect(page.getByRole("button", { name: "Saved", exact: true })).toBeVisible();
});

test("a saved list disappears from Saved once visibility no longer permits it (friendship removed), but a public save survives", async ({
  page,
}) => {
  await signIn(page, friend);

  // Save both the friends list and the public list.
  await page.goto("/lists");
  const sharedSection = getSection(page, "Shared with me");
  await sharedSection.getByRole("button", { name: "Save", exact: true }).click();
  await expect(sharedSection.getByRole("button", { name: "Saved", exact: true })).toBeVisible();

  await page.goto(`/lists/${publicListId}`);
  const saveBtn = page.getByRole("button", { name: "Save", exact: true });
  if (await saveBtn.isVisible().catch(() => false)) {
    await saveBtn.click();
  }

  await page.goto("/lists");
  const savedBefore = getSection(page, "Saved");
  await expect(savedBefore.getByText("PW Friends List")).toBeVisible();
  await expect(savedBefore.getByText("PW Public List")).toBeVisible();

  // Remove the friendship directly, simulating it happening elsewhere.
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", owner.id)
    .eq("addressee_id", friend.id);

  await page.reload();
  const savedSection = page.locator("section", { hasText: "Saved" }).last();
  await expect(savedSection.getByText("PW Friends List")).toHaveCount(0);
  await expect(savedSection.getByText("PW Public List")).toBeVisible();
  await expect(page.getByText("No lists have been shared with you yet.")).toBeVisible();

  // Restore the friendship for any later tests / cleanup symmetry.
  await supabase
    .from("friendships")
    .insert({ requester_id: owner.id, addressee_id: friend.id, status: "accepted" });
});
