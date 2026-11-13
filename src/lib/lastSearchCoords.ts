const KEY = "sms:lastSearchCoords";

// Shared sentinel for the location field: pages that let a user pick
// coordinates via "Use my location" fill the field with this label rather
// than a real address, so a subsequent submit knows to reuse the cached
// coords instead of re-geocoding the label text itself.
export const CURRENT_LOCATION_LABEL = "Current location";

export type Coords = { lat: number; lng: number };

// sessionStorage, not localStorage - "the last-used coordinates from this
// session," not a permanent remembered location across visits.
export function getLastSearchCoords(): Coords | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (typeof parsed?.lat === "number" && typeof parsed?.lng === "number") {
      return { lat: parsed.lat, lng: parsed.lng };
    }
    return null;
  } catch {
    return null;
  }
}

export function setLastSearchCoords(coords: Coords) {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(KEY, JSON.stringify(coords));
  } catch {
    // ignore - e.g. private browsing storage restrictions
  }
}

const AREA_KEY = "sms:lastSearchArea";

// The last results page search in this session: its area, point and Where text, so coming back
// to the results page (the logo, the Search tab) returns to the same map. Session-only.
export type LastSearchArea = {
  b: { west: number; south: number; east: number; north: number };
  lat: number;
  lng: number;
  where: string;
};

export function getLastSearchArea(): LastSearchArea | null {
  if (typeof window === "undefined") return null;
  try {
    const parsed = JSON.parse(sessionStorage.getItem(AREA_KEY) ?? "null");
    const b = parsed?.b;
    const ok =
      b && [b.west, b.south, b.east, b.north, parsed.lat, parsed.lng].every((n) => typeof n === "number" && Number.isFinite(n));
    return ok ? { b, lat: parsed.lat, lng: parsed.lng, where: typeof parsed.where === "string" ? parsed.where : "" } : null;
  } catch {
    return null;
  }
}

export function setLastSearchArea(area: LastSearchArea) {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(AREA_KEY, JSON.stringify(area));
  } catch {
    // ignore
  }
}
