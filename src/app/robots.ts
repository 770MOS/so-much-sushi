import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/siteUrl";

// While the site is in private testing (SITE_REQUIRE_LOGIN=1), search engines are asked to stay
// out: every page sends visitors to sign-in anyway. Once browsing opens, place pages and public
// lists are listed in the sitemap. Built with the site, so it changes on the next deploy after
// the setting does.
export default function robots(): MetadataRoute.Robots {
  if (process.env.SITE_REQUIRE_LOGIN === "1") {
    return { rules: { userAgent: "*", disallow: "/" } };
  }
  return { rules: { userAgent: "*", allow: "/" }, sitemap: `${SITE_URL}/sitemap.xml` };
}
