import { test, expect } from "@playwright/test";
import dotenv from "dotenv";
import { createClient } from "@supabase/supabase-js";

dotenv.config({ path: ".env.local" });

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

const PASSWORD = "TestPassword123!";
// The handle input has a real maxLength={20} - keep generated handles well
// under that (a longer RUN_ID here silently truncates on .fill(), which
// then desyncs from what's actually stored in the DB and breaks the
// handle-availability check in a confusing way).
const RUN_ID = Date.now().toString(36).slice(-6);

const takenHandleUser = {
  id: "",
  email: `test+signuptaken-${RUN_ID}@example.com`,
  handle: `pwsu_tkn_${RUN_ID}`,
};

async function fillSignUpForm(
  page: import("@playwright/test").Page,
  fields: { email: string; firstName: string; lastName: string; handle: string; password: string; confirmPassword: string }
) {
  await page.goto("/sign-up");
  await page.locator("#email").fill(fields.email);
  await page.locator("#first-name").fill(fields.firstName);
  await page.locator("#last-name").fill(fields.lastName);
  await page.locator("#handle").fill(fields.handle);
  await page.locator("#password").fill(fields.password);
  await page.locator("#confirm-password").fill(fields.confirmPassword);
}

test.beforeAll(async () => {
  const { data, error } = await supabase.auth.admin.createUser({
    email: takenHandleUser.email,
    password: PASSWORD,
    email_confirm: true,
  });
  if (error || !data.user) throw new Error(`Failed to create ${takenHandleUser.email}: ${error?.message}`);
  takenHandleUser.id = data.user.id;

  const { error: profileError } = await supabase
    .from("profiles")
    .update({ handle: takenHandleUser.handle })
    .eq("id", takenHandleUser.id);
  if (profileError) throw new Error(`Failed to set handle: ${profileError.message}`);
});

test.afterAll(async () => {
  if (takenHandleUser.id) await supabase.auth.admin.deleteUser(takenHandleUser.id);
});

test("shows an error when passwords don't match, without attempting to create an account", async ({
  page,
}) => {
  await fillSignUpForm(page, {
    email: `test+signupmismatch-${RUN_ID}@example.com`,
    firstName: "Test",
    lastName: "Mismatch",
    handle: `pwsu_mis_${RUN_ID}`,
    password: "ValidPass123!",
    confirmPassword: "DifferentPass123!",
  });

  await page.getByRole("button", { name: "Sign up", exact: true }).click();

  await expect(page.getByText("Passwords don't match.")).toBeVisible();
  // Still on the form, not the "check your email" screen - confirms no
  // signUp() call was ever made for a validation failure like this.
  await expect(page.locator("#email")).toBeVisible();
});

test("shows an error when the handle is already taken", async ({ page }) => {
  await fillSignUpForm(page, {
    email: `test+signupnewemail-${RUN_ID}@example.com`,
    firstName: "Test",
    lastName: "Taken",
    handle: takenHandleUser.handle,
    password: "ValidPass123!",
    confirmPassword: "ValidPass123!",
  });

  await page.getByRole("button", { name: "Sign up", exact: true }).click();

  await expect(page.getByText("That handle is already taken. Please choose another.")).toBeVisible();
});

test("completes sign-up with valid details and shows the confirm-email message", async ({ page }) => {
  // Exercises the real supabase.auth.signUp() call end to end. Since email
  // confirmation is enabled for this project, success means landing on the
  // "check your email" message, not a redirect - there's no session yet.
  // Uses a fresh, timestamp-unique email each run; cleaned up via
  // scripts/delete-test-users.mjs (matches the test+ convention).
  await fillSignUpForm(page, {
    email: `test+signupsuccess-${RUN_ID}@example.com`,
    firstName: "Test",
    lastName: "Success",
    handle: `pwsu_ok_${RUN_ID}`,
    password: "ValidPass123!",
    confirmPassword: "ValidPass123!",
  });

  await page.getByRole("button", { name: "Sign up", exact: true }).click();

  await expect(
    page.getByText("Check your email to confirm your account before signing in.")
  ).toBeVisible({ timeout: 15_000 });
});
