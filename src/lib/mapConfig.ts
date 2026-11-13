// Isolates the map tile/style source so swapping providers later (e.g. to a
// self-hosted PMTiles source) is a small, contained change - nothing outside
// this file should know the source is MapTiler.

const MAPTILER_API_KEY = process.env.NEXT_PUBLIC_MAPTILER_API_KEY;

export function getMapStyleUrl(): string {
  if (!MAPTILER_API_KEY) {
    throw new Error("NEXT_PUBLIC_MAPTILER_API_KEY is not set");
  }
  // MapTiler's "Base" style, v4, light variant (2026-11-13): pale grey
  // streets with street and neighbourhood names, and no shop, petrol-station
  // or restaurant icons of its own, so nothing competes with our pins and it
  // matches the site's white look. v4 is MapTiler's current generation and a
  // fixed ID, so it won't change under us. (Streets v4 has no light variant -
  // "streets-v4-light" returns 404 - and "streets-v2-light" is deprecated.)
  return `https://api.maptiler.com/maps/base-v4-light/style.json?key=${MAPTILER_API_KEY}`;
}

export const DEFAULT_MAP_CENTER: [number, number] = [-77.1, 38.88]; // [lng, lat]
export const DEFAULT_MAP_ZOOM = 12;
