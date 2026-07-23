// Isolates the map tile/style source so swapping providers later (e.g. to a
// self-hosted PMTiles source) is a small, contained change - nothing outside
// this file should know the source is MapTiler.

const MAPTILER_API_KEY = process.env.NEXT_PUBLIC_MAPTILER_API_KEY;

export function getMapStyleUrl(): string {
  if (!MAPTILER_API_KEY) {
    throw new Error("NEXT_PUBLIC_MAPTILER_API_KEY is not set");
  }
  // MapTiler's "Streets" style, v4 - the current version (v2 still
  // resolves too, kept for reference, but v4 is the newer of the two and
  // isn't a floating/unpinned alias, so it won't change out from under us
  // silently).
  return `https://api.maptiler.com/maps/streets-v4/style.json?key=${MAPTILER_API_KEY}`;
}

export const DEFAULT_MAP_CENTER: [number, number] = [-77.1, 38.88]; // [lng, lat]
export const DEFAULT_MAP_ZOOM = 12;
