import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Renamed pages (2026-11-12): Starred became Favorites and Connections became
  // Friends. Temporary redirects, so old bookmarks still work without browsers
  // caching the move forever.
  async redirects() {
    return [
      { source: "/starred", destination: "/favorites", permanent: false },
      { source: "/connections", destination: "/friends", permanent: false },
    ];
  },
};

export default nextConfig;
