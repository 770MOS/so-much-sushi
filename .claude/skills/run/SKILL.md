---
name: run
description: Launch the so-much-sushi Next.js dev server and drive it in headless Chromium (via Playwright) to visually verify UI changes. Use this whenever asked to run, start, screenshot, or verify the app in a browser.
---

# Running and verifying so-much-sushi

This is a Next.js App Router app (`npm run dev`). Browser-driven
verification needs a headless Chromium, which is not installed in a
fresh environment — set it up once per environment with the steps
below, then reuse it for every future verification run.

## 1. Start the dev server

```bash
npm run dev &   # or with run_in_background: true if using a tool that tracks it
```

Next.js prints the actual port to stdout — it falls back to 3001 (or
higher) if 3000 is already taken by another process, so don't assume
3000. Poll for readiness instead of guessing:

```bash
timeout 30 bash -c 'until curl -sf http://localhost:3001 >/dev/null; do sleep 1; done'
```

Stop it with `pkill -f "next dev"` before relaunching, or the next run
prints a port-conflict warning (not fatal, but noisy).

## 2. One-time Chromium setup (skip if already done)

`chromium-cli` is not available in this environment. Use the
`playwright` npm package directly instead:

```bash
npx --yes playwright install chromium   # downloads ~170MB, cached at
                                          # ~/Library/Caches/ms-playwright — only needed once per machine
```

The browser binary is cached globally per-machine, not per-project, so
this step is skipped automatically on future runs once it's been done
once on a given machine.

## 3. Get the `playwright` package resolvable

`npx playwright install` only downloads the browser binary — it does
**not** make `import { chromium } from "playwright"` resolvable from a
plain `node script.mjs`. Install the package into the project without
touching `package.json`/committing it as a real dependency:

```bash
npm install --no-save playwright
```

`--no-save` keeps `package.json` and `package-lock.json` untouched
(verify with `git status` / `git diff` after — there should be no
diff). Remove it again when done: `npm uninstall playwright`.

**Gotcha:** the driver script must live *inside* the project directory
(anywhere under `so-much-sushi/`), not in `/tmp` or a scratchpad —
Node's ESM resolver walks up from the script's own file path to find
`node_modules`, not from `cwd`. A script outside the project tree will
fail with `ERR_MODULE_NOT_FOUND: Cannot find package 'playwright'`
even though the package is installed. Write it as e.g.
`verify_tmp.mjs` at the project root (must end in `.mjs`, plain `.tmp`
extensions fail Node's format detection), run it, then delete it — it's
throwaway, not something to commit.

## 4. Drive it

```js
import { chromium } from "playwright";

const browser = await chromium.launch();
const page = await browser.newPage();

const consoleErrors = [];
page.on("console", (msg) => { if (msg.type() === "error") consoleErrors.push(msg.text()); });
page.on("pageerror", (err) => consoleErrors.push(err.message));

await page.goto("http://localhost:3001", { waitUntil: "networkidle" });
await page.waitForSelector("#location", { state: "visible" });
await page.screenshot({ path: "/absolute/path/to/scratchpad/step.png", fullPage: true });

// Interact like a user, not via el.value = ... (React controlled inputs
// won't see raw DOM mutation). Use fill/click/selectOption/keyboard:
await page.fill("#location", "Arlington, VA 22203");
await page.click('button[type="submit"]');
await page.waitForSelector("text=/\\d+ results?/", { timeout: 15000 });

console.log("console/page errors:", consoleErrors);
await browser.close();
```

Run with plain `node` (not `npx tsx` — this project has no TS script
runner installed):

```bash
node /Users/johnny/Projects/so-much-sushi/verify_tmp.mjs
```

Read screenshots back with the Read tool to actually look at them —
producing a screenshot without viewing it doesn't verify anything.

## App-specific notes

- The root page (`src/app/page.tsx`) is a client component with a
  location input (`#location`), radius slider (`#radius`, native
  `type="range"` — use `focus()` + `keyboard.press("Home"/"End")` or
  arrow keys to change it, not `fill()`), a category `<select>`
  (`#category`), and a submit button (`button[type="submit"]`).
- Geocoding hits the real Nominatim API client-side. Bare ZIP codes
  (e.g. `"22203"`) are ambiguous and can resolve to the wrong country —
  use a fuller string like `"Arlington, VA 22203"` for reliable
  happy-path tests.
- Search results render as `ul li` with the name in
  `span.font-medium`; the "Nearest"/"A–Z" sort buttons only appear
  once `results.length > 0`.

## Cleanup checklist after verifying

```bash
pkill -f "next dev"
rm -f /Users/johnny/Projects/so-much-sushi/verify_tmp.mjs
npm uninstall playwright   # optional — leave installed if you expect to verify again soon
git status --short         # confirm no stray diffs in package.json/package-lock.json
```
