// Roughly where a first-time visitor is, so the map can start near them (decided 2026-11-10).
//
// Vercel adds the visitor's city, region and an approximate point, worked out from their
// internet address, to each request it serves (x-vercel-ip-* headers; city level, free).
// This hands those back to the page and nothing else: the address itself is never read here,
// and nothing is logged or stored. Outside Vercel (local development) the headers aren't
// there and the answer is { area: null }, as it is for visitors outside the United States.

import type { IpArea } from "@/lib/ipArea";

function decoded(value: string | null): string {
  if (!value) return "";
  try {
    return decodeURIComponent(value).trim();
  } catch {
    return value.trim();
  }
}

export async function GET(request: Request) {
  const h = request.headers;
  const lat = Number(h.get("x-vercel-ip-latitude"));
  const lng = Number(h.get("x-vercel-ip-longitude"));
  const country = h.get("x-vercel-ip-country");
  const city = decoded(h.get("x-vercel-ip-city"));
  const region = decoded(h.get("x-vercel-ip-country-region"));

  const known =
    country === "US" &&
    h.get("x-vercel-ip-latitude") !== null &&
    h.get("x-vercel-ip-longitude") !== null &&
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    Math.abs(lat) <= 90 &&
    Math.abs(lng) <= 180;

  const area: IpArea | null = known
    ? { lat, lng, label: [city, /^[A-Z]{2}$/.test(region) ? region : ""].filter(Boolean).join(", ") }
    : null;

  // Personal to this visitor: never cached by a browser cache shared with others or by a CDN.
  return Response.json({ area }, { headers: { "Cache-Control": "private, no-store" } });
}
