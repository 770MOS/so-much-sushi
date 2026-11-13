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

const LABEL_KEY = "sms:lastSearchLabel";

// The place name shown for the last search point ("Clarendon, Arlington, VA"), so the
// results page can come back to it in the same words. Session-only, like the point.
export function getLastSearchLabel(): string | null {
  if (typeof window === "undefined") return null;
  try {
    return sessionStorage.getItem(LABEL_KEY);
  } catch {
    return null;
  }
}

export function setLastSearchLabel(label: string) {
  if (typeof window === "undefined") return;
  try {
    if (label.trim()) sessionStorage.setItem(LABEL_KEY, label.trim());
  } catch {
    // ignore
  }
}
