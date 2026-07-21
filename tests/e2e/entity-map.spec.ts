import { test, expect } from "@playwright/test";

// Regression test for a CSS specificity bug: EntityMap's createMarkerElement
// set an inline `position: relative` on the element handed to
// `new maplibregl.Marker({ element })`, which silently overrode
// maplibre-gl.css's required `.maplibregl-marker { position: absolute }`
// rule (inline styles beat class selectors). That left every marker in
// normal document flow instead of absolutely positioned by MapLibre's own
// transform, so markers stacked one below the next (~36px per marker -
// its own height) rather than at their real map position. Visually this
// looked like every restaurant pin collapsing into a single vertical line,
// even though the underlying lat/lng data and MapLibre's computed
// transform offsets were both correct the whole time.
test.use({
  geolocation: { latitude: 38.8769326, longitude: -77.0893094 },
  permissions: ["geolocation"],
});

test("map view spreads markers across real positions instead of stacking in a line", async ({
  page,
}) => {
  await page.goto("/");

  // Max radius from the Arlington-centered mocked location covers the
  // whole current (small, single-county) dataset - enough markers that a
  // stacking bug would be obvious, not just one or two data points.
  await page.locator("#radius").fill("25");
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByText(/results/)).toBeVisible({ timeout: 15_000 });

  await page.getByRole("button", { name: "Map", exact: true }).click();
  await expect(page.locator(".maplibregl-map")).toBeVisible();
  await expect(page.locator(".maplibregl-marker").first()).toBeVisible({ timeout: 15_000 });
  // Let MapLibre finish its initial fitBounds/marker placement pass.
  await page.waitForTimeout(2000);

  const { containerRect, markerRects } = await page.evaluate(() => {
    const container = document.querySelector(".maplibregl-map")!.getBoundingClientRect();
    const markers = Array.from(document.querySelectorAll(".maplibregl-marker")).map((m) =>
      m.getBoundingClientRect()
    );
    return {
      containerRect: { x: container.x, y: container.y, width: container.width, height: container.height },
      markerRects: markers.map((r) => ({ x: r.x, y: r.y })),
    };
  });

  // Sanity check there's actually a meaningful number of markers to assert
  // over, not a near-empty result set that would make the checks below
  // pass trivially.
  expect(markerRects.length).toBeGreaterThan(50);

  // The bug's clearest symptom: markers rendered thousands of pixels below
  // the map, entirely outside its bounds. Every marker should actually
  // render inside (a small margin for anchor/transform rounding).
  for (const rect of markerRects) {
    expect(rect.y).toBeGreaterThanOrEqual(containerRect.y - 50);
    expect(rect.y).toBeLessThanOrEqual(containerRect.y + containerRect.height + 50);
  }

  // And a real 2D spread, not everything clustered at a single x (the
  // visual "single vertical line" symptom).
  const xs = markerRects.map((r) => r.x);
  const xRange = Math.max(...xs) - Math.min(...xs);
  expect(xRange).toBeGreaterThan(containerRect.width * 0.5);
});
