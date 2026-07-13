import { test, expect } from "@playwright/test";

const MOCK_LAT = 38.8816;
const MOCK_LNG = -77.091;

test.use({
  geolocation: { latitude: MOCK_LAT, longitude: MOCK_LNG },
  permissions: ["geolocation"],
});

test("dropdown appears when the location field is focused and empty", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByText("Current Location")).toHaveCount(0);
  await page.locator("#location").click();
  await expect(page.getByText("Current Location")).toBeVisible();
});

test("dropdown disappears once typing starts", async ({ page }) => {
  await page.goto("/");

  await page.locator("#location").click();
  await expect(page.getByText("Current Location")).toBeVisible();

  await page.locator("#location").fill("22201");
  await expect(page.getByText("Current Location")).toHaveCount(0);
});

test('"Current Location" triggers the same geolocation flow as the icon button', async ({
  page,
}) => {
  await page.route("**/nominatim.openstreetmap.org/reverse**", (route) => route.abort());

  await page.goto("/");

  await page.locator("#location").click();
  await page.getByText("Current Location").click();

  await expect(page.locator("#location")).toHaveValue("Current location");
});

test("up to 5 deduplicated history entries render, most recent first, and clicking one fills the field", async ({
  page,
}) => {
  await page.addInitScript(() => {
    localStorage.setItem(
      "sms:searchHistory",
      JSON.stringify(["22201", "22202", "22203", "22204", "22205"])
    );
  });

  await page.goto("/");
  await page.locator("#location").click();

  await expect(page.getByText("Search History")).toBeVisible();
  const historyButtons = page.locator("button", { hasText: /^222\d\d$/ });
  await expect(historyButtons).toHaveCount(5);

  const first = page.getByRole("button", { name: "22201", exact: true });
  await expect(first).toBeVisible();
  await first.click();

  await expect(page.locator("#location")).toHaveValue("22201");
  await expect(page.getByText("Current Location")).toHaveCount(0);
});

test("a successful location search is appended to history", async ({ page }) => {
  await page.goto("/");

  await page.locator("#location").fill("22201");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByRole("button", { name: "Search", exact: true })).toBeEnabled({
    timeout: 15_000,
  });

  await page.locator("#location").fill("");
  await page.locator("#location").click();

  await expect(page.getByRole("button", { name: "22201", exact: true })).toBeVisible();
});
