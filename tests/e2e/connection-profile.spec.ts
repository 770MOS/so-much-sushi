import { test, expect } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const PASSWORD = "TestPassword123!";
const RUN_ID = Date.now().toString(36);

type TestUser = { id: string; email: string; handle: string };

const ownerA: TestUser = {
  id: "",
  email: `test+profileA-${RUN_ID}@example.com`,
  handle: `pw-owner-a-${RUN_ID}`,
};
const friendOfA: TestUser = {
  id: "",
  email: `test+profileFriend-${RUN_ID}@example.com`,
  handle: `pw-friend-${RUN_ID}`,
};
const stranger: TestUser = {
  id: "",
  email: `test+profileStranger-${RUN_ID}@example.com`,
  handle: `pw-stranger-${RUN_ID}`,
};
const ownerB: TestUser = {
  id: "",
  email: `test+profileB-${RUN_ID}@example.com`,
  handle: `pw-owner-b-${RUN_ID}`,
};

let starredEntityId: string;
let friendsListId: string;
let privateListId: string;
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
    .update({ handle: user.handle, display_name: displayName })
    .eq("id", user.id);
  if (profileError) throw new Error(`Failed to set profile for ${user.email}: ${profileError.message}`);
}

async function signIn(page: import("@playwright/test").Page, user: TestUser) {
  await page.goto("/sign-in");
  await page.locator("#email").fill(user.email);
  await page.locator("#password").fill(PASSWORD);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  // The button's accessible name flips to "Signing in..." the instant
  // `loading` goes true (synchronous on click) - waiting for it to
  // disappear proves nothing about whether sign-in actually completed.
  // Wait for the real post-login redirect (router.push("/")) instead.
  await page.waitForURL("/", { timeout: 15_000 });
}

test.beforeAll(async () => {
  await createTestUser(ownerA, "Owner A");
  await createTestUser(friendOfA, "Friend Of A");
  await createTestUser(stranger, "Stranger");
  await createTestUser(ownerB, "Owner B");

  const { error: friendError } = await supabase.from("friendships").insert({
    requester_id: ownerA.id,
    addressee_id: friendOfA.id,
    status: "accepted",
  });
  if (friendError) throw new Error(`Failed to create friendship: ${friendError.message}`);

  const { data: entity, error: entityError } = await supabase
    .from("entities")
    .select("id")
    .limit(1)
    .single();
  if (entityError || !entity) throw new Error(`Failed to find an entity to star: ${entityError?.message}`);
  starredEntityId = entity.id;

  const { error: starError } = await supabase
    .from("stars")
    .insert({ user_id: ownerA.id, entity_id: starredEntityId });
  if (starError) throw new Error(`Failed to star entity for ownerA: ${starError.message}`);

  const { data: friendsList, error: friendsListError } = await supabase
    .from("lists")
    .insert({ owner_id: ownerA.id, name: "PW Friends List", visibility: "friends" })
    .select("id")
    .single();
  if (friendsListError || !friendsList) {
    throw new Error(`Failed to create friends list: ${friendsListError?.message}`);
  }
  friendsListId = friendsList.id;

  const { data: privateList, error: privateListError } = await supabase
    .from("lists")
    .insert({ owner_id: ownerA.id, name: "PW Private List", visibility: "private" })
    .select("id")
    .single();
  if (privateListError || !privateList) {
    throw new Error(`Failed to create private list: ${privateListError?.message}`);
  }
  privateListId = privateList.id;

  const { data: publicList, error: publicListError } = await supabase
    .from("lists")
    .insert({ owner_id: ownerB.id, name: "PW Public List", visibility: "public" })
    .select("id")
    .single();
  if (publicListError || !publicList) {
    throw new Error(`Failed to create public list: ${publicListError?.message}`);
  }
  publicListId = publicList.id;
});

test.afterAll(async () => {
  const listIds = [friendsListId, privateListId, publicListId].filter(Boolean);
  if (listIds.length) await supabase.from("lists").delete().in("id", listIds);
  if (starredEntityId) {
    await supabase.from("stars").delete().eq("user_id", ownerA.id).eq("entity_id", starredEntityId);
  }
  await supabase
    .from("friendships")
    .delete()
    .eq("requester_id", ownerA.id)
    .eq("addressee_id", friendOfA.id);

  for (const user of [ownerA, friendOfA, stranger, ownerB]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("stranger sees only name/avatar and empty Starred/Lists (no public lists)", async ({ page }) => {
  await signIn(page, stranger);
  await page.goto(`/u/${ownerA.handle}`);

  await expect(page.getByRole("heading", { name: "Owner A" })).toBeVisible();
  await expect(page.getByText(`@${ownerA.handle}`)).toBeVisible();

  await expect(page.getByText("Nothing to show")).toHaveCount(2);
  await expect(page.getByText("PW Friends List")).toHaveCount(0);
  await expect(page.getByText("PW Private List")).toHaveCount(0);
});

test("accepted connection sees the starred list and friends-visibility lists", async ({ page }) => {
  await signIn(page, friendOfA);
  await page.goto(`/u/${ownerA.handle}`);

  await expect(page.getByRole("heading", { name: "Owner A" })).toBeVisible();

  const starredEntityName = await supabase
    .from("entities")
    .select("name")
    .eq("id", starredEntityId)
    .single()
    .then((r) => r.data?.name);
  await expect(page.getByText(starredEntityName!)).toBeVisible();

  await expect(page.getByText("PW Friends List")).toBeVisible();
  await expect(page.getByText("PW Private List")).toHaveCount(0);
});

test("a public list shows to everyone regardless of connection status", async ({ page }) => {
  // Stranger has no friendship with ownerB at all - proves visibility here
  // isn't connection-gated.
  await signIn(page, stranger);
  await page.goto(`/u/${ownerB.handle}`);

  const listLink = page.getByRole("link", { name: "PW Public List" });
  await expect(listLink).toBeVisible();
  await expect(listLink).toHaveAttribute("href", `/lists/${publicListId}`);
});

test("an unauthenticated visitor also sees the public list", async ({ browser }) => {
  const context = await browser.newContext();
  const page = await context.newPage();

  await page.goto(`/u/${ownerB.handle}`);
  await expect(page.getByRole("link", { name: "PW Public List" })).toBeVisible();

  await context.close();
});

test("visiting your own handle redirects to /profile", async ({ page }) => {
  await signIn(page, ownerA);
  await page.goto(`/u/${ownerA.handle}`);

  await expect(page).toHaveURL(/\/profile/);
});
