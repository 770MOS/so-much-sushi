// The app's real public origin - needed anywhere an absolute URL has to be
// built outside the browser (sitemap.ts can't use window.location; the
// Share button can and does use window.location.origin instead, so it
// doesn't depend on this). Falls back to localhost for local dev so
// nothing breaks out of the box, but production deploys must set
// NEXT_PUBLIC_SITE_URL to the real domain or the sitemap will emit
// localhost URLs.
export const SITE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
