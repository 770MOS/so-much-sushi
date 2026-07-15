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

const owner: TestUser = { id: "", email: `test+plo${RUN_ID}@example.com`, handle: `pwpl_o_${RUN_ID}` };
const friend: TestUser = { id: "", email: `test+plf${RUN_ID}@example.com`, handle: `pwpl_f_${RUN_ID}` };
const stranger: TestUser = { id: "", email: `test+pls${RUN_ID}@example.com`, handle: `pwpl_s_${RUN_ID}` };

let entityId: string;
let entityName: string;
let friendsListId: string;

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
  await createTestUser(owner, "Profile Links Owner");
  await createTestUser(friend, "Profile Links Friend");
  await createTestUser(stranger, "Profile Links Stranger");

  const { error: friendErr } = await supabase
    .from("friendships")
    .insert({ requester_id: owner.id, addressee_id: friend.id, status: "accepted" });
  if (friendErr) throw new Error(`Failed to create friendship: ${friendErr.message}`);

  const { error: pendingErr } = await supabase
    .from("friendships")
    .insert({ requester_id: stranger.id, addressee_id: owner.id, status: "pending" });
  if (pendingErr) throw new Error(`Failed to create pending request: ${pendingErr.message}`);

  const { data: entity, error: entityErr } = await supabase
    .from("entities")
    .select("id, name")
    .limit(1)
    .single();
  if (entityErr || !entity) throw new Error(`Failed to find an entity: ${entityErr?.message}`);
  entityId = entity.id;
  entityName = entity.name;

  const { error: starErr } = await supabase.from("stars").insert({ user_id: owner.id, entity_id: entityId });
  if (starErr) throw new Error(`Failed to star entity: ${starErr.message}`);

  const { data: list, error: listErr } = await supabase
    .from("lists")
    .insert({ owner_id: owner.id, name: "PW Profile Links Friends List", visibility: "friends" })
    .select("id")
    .single();
  if (listErr || !list) throw new Error(`Failed to create list: ${listErr?.message}`);
  friendsListId = list.id;
});

test.afterAll(async () => {
  await supabase.from("lists").delete().eq("id", friendsListId);
  await supabase.from("stars").delete().eq("user_id", owner.id).eq("entity_id", entityId);
  await supabase
    .from("friendships")
    .delete()
    .or(`requester_id.eq.${owner.id},addressee_id.eq.${owner.id}`);
  for (const user of [owner, friend, stranger]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("Connections list links each connection's name to their /u/[handle]", async ({ page }) => {
  await signIn(page, friend);
  await page.goto("/connections");

  const link = page.getByRole("link", { name: "Profile Links Owner" });
  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute("href", `/u/${owner.handle}`);

  await link.click();
  await expect(page).toHaveURL(new RegExp(`/u/${owner.handle}$`));
  await expect(page.getByRole("heading", { name: "Profile Links Owner" })).toBeVisible();
});

test("incoming and outgoing connection request names link to /u/[handle]", async ({ page, browser }) => {
  await signIn(page, owner);
  await page.goto("/connections");

  const incoming = page.getByRole("link", { name: "Profile Links Stranger" });
  await expect(incoming).toHaveAttribute("href", `/u/${stranger.handle}`);
  await incoming.click();
  await expect(page).toHaveURL(new RegExp(`/u/${stranger.handle}$`));

  const strangerPage = await (await browser.newContext()).newPage();
  await signIn(strangerPage, stranger);
  await strangerPage.goto("/connections");

  const outgoing = strangerPage.getByRole("link", { name: "Profile Links Owner" });
  await expect(outgoing).toHaveAttribute("href", `/u/${owner.handle}`);
  await outgoing.click();
  await expect(strangerPage).toHaveURL(new RegExp(`/u/${owner.handle}$`));
});

test("Shared with me owner_name on /lists links to /u/[handle]", async ({ page }) => {
  await signIn(page, friend);
  await page.goto("/lists");

  const link = page.getByRole("link", { name: "Profile Links Owner" });
  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute("href", `/u/${owner.handle}`);

  await link.click();
  await expect(page).toHaveURL(new RegExp(`/u/${owner.handle}$`));
});

test('search result "Starred by [name]" links to /u/[handle]', async ({ page }) => {
  await signIn(page, friend);
  await page.goto("/search");

  await page.locator("#name").fill(entityName);
  await page.getByRole("button", { name: "Search", exact: true }).click();

  await expect(page.getByText("Starred by")).toBeVisible({ timeout: 15_000 });
  const link = page.getByRole("link", { name: "Profile Links Owner" });
  await expect(link).toBeVisible();
  await expect(link).toHaveAttribute("href", `/u/${owner.handle}`);

  await link.click();
  await expect(page).toHaveURL(new RegExp(`/u/${owner.handle}$`));
});
