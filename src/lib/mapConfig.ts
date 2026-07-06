// Isolates the map tile/style source so swapping providers later (e.g. to a
// self-hosted PMTiles source) is a small, contained change - nothing outside
// this file should know the source is MapTiler.

const MAPTILER_API_KEY = process.env.NEXT_PUBLIC_MAPTILER_API_KEY;

export function getMapStyleUrl(): string {
  if (!MAPTILER_API_KEY) {
    throw new Error("NEXT_PUBLIC_MAPTILER_API_KEY is not set");
  }
  // MapTiler's "Basic" style - soft, muted, minimal palette consistent with
  // the app's neutral aesthetic elsewhere.
  return `https://api.maptiler.com/maps/basic-v2/style.json?key=${MAPTILER_API_KEY}`;
}

export const DEFAULT_MAP_CENTER: [number, number] = [-77.1, 38.88]; // [lng, lat]
export const DEFAULT_MAP_ZOOM = 12;
