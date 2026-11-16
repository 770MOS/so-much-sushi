// The app's real public origin - needed anywhere an absolute URL has to be
// built outside the browser (sitemap.ts and robots.ts can't use
// window.location; the Share button can and does use window.location.origin
// instead, so it doesn't depend on this).
// In order: NEXT_PUBLIC_SITE_URL if set; on Vercel, the project's production
// address (VERCEL_PROJECT_PRODUCTION_URL: the custom domain once there is
// one, else the vercel.app address; server-side only); else localhost for
// local dev.
const vercelProduction = process.env.VERCEL_PROJECT_PRODUCTION_URL;
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ||
  (vercelProduction ? `https://${vercelProduction}` : "http://localhost:3000");
