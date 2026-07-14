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

const userA: TestUser = { id: "", email: `test+conna${RUN_ID}@example.com`, handle: `pwconn_a_${RUN_ID}` };
const userB: TestUser = { id: "", email: `test+connb${RUN_ID}@example.com`, handle: `pwconn_b_${RUN_ID}` };
const userC: TestUser = { id: "", email: `test+connc${RUN_ID}@example.com`, handle: `pwconn_c_${RUN_ID}` };

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
    // home_city/home_state set so the (unrelated) first-sign-in home
    // location prompt never appears and its overlay doesn't intercept
    // clicks in these tests.
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

test.beforeAll(async () => {
  await createTestUser(userA, "Conn User A");
  await createTestUser(userB, "Conn User B");
  await createTestUser(userC, "Conn User C");

  // C -> A pending request, seeded directly, to test the incoming/decline
  // path without needing a fourth sign-in.
  const { error } = await supabase
    .from("friendships")
    .insert({ requester_id: userC.id, addressee_id: userA.id, status: "pending" });
  if (error) throw new Error(`Failed to seed C->A request: ${error.message}`);
});

test.afterAll(async () => {
  const ids = [userA.id, userB.id, userC.id].filter(Boolean);
  if (ids.length) {
    await supabase.from("friendships").delete().or(ids.map((id) => `requester_id.eq.${id}`).join(","));
    await supabase.from("friendships").delete().or(ids.map((id) => `addressee_id.eq.${id}`).join(","));
  }
  for (const user of [userA, userB, userC]) {
    if (user.id) await supabase.auth.admin.deleteUser(user.id);
  }
});

test("sidebar Connections link navigates to the dedicated /connections route", async ({ page }) => {
  await signIn(page, userA);
  await page.locator('nav[aria-label="Main"]:visible').getByRole("link", { name: "Connections" }).click();
  await expect(page).toHaveURL(/\/connections$/);
  await expect(page.locator("h1").getByText("Connections")).toBeVisible();
});

test("/profile no longer has a Connections tab", async ({ page }) => {
  await signIn(page, userA);
  await page.goto("/profile");

  await expect(page.getByRole("button", { name: "Starred", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Lists", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Connections", exact: true })).toHaveCount(0);
  await expect(page.getByText("Find people")).toHaveCount(0);
});

test("the old ?tab=connections deep link falls back sensibly instead of breaking", async ({ page }) => {
  await signIn(page, userA);
  await page.goto("/profile?tab=connections");

  // Falls back to the default (Starred) tab rather than erroring or showing
  // a blank/broken Connections tab that no longer exists.
  await expect(page.getByRole("button", { name: "Starred", exact: true })).toHaveAttribute(
    "class",
    /bg-primary/
  );
  await expect(page.getByText("Find people")).toHaveCount(0);
});

test("search, send request, decline, and accept all work on /connections", async ({ page, browser }) => {
  await signIn(page, userA);
  await page.goto("/connections");

  // Incoming request from C, seeded in beforeAll.
  await expect(page.getByText("Incoming requests (1)")).toBeVisible();
  await expect(page.getByText("Conn User C")).toBeVisible();
  await page.getByRole("button", { name: "Decline" }).click();
  await expect(page.getByText("No incoming requests.")).toBeVisible();

  // Search for B and send a request.
  await page.locator('input[placeholder="Search by handle"]').fill(userB.handle);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText("Conn User B")).toBeVisible();
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.getByText("Requested")).toBeVisible();

  // As B, accept the incoming request from A.
  const bPage = await (await browser.newContext()).newPage();
  await signIn(bPage, userB);
  await bPage.goto("/connections");
  await expect(bPage.getByText("Incoming requests (1)")).toBeVisible();
  await expect(bPage.getByText("Conn User A")).toBeVisible();
  await bPage.getByRole("button", { name: "Accept" }).click();
  await expect(bPage.getByText("Connections (1)")).toBeVisible();
  await expect(bPage.getByText("Conn User A").last()).toBeVisible();

  // Back as A, confirm B now shows under Connections, then remove it.
  await page.reload();
  await expect(page.getByText("Connections (1)")).toBeVisible();
  await expect(page.getByText("Conn User B")).toBeVisible();
  await page.getByRole("button", { name: "Remove" }).click();
  await expect(page.getByText("You haven't connected with anyone yet.")).toBeVisible();
});
