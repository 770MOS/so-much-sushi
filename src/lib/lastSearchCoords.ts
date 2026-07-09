const KEY = "sms:lastSearchCoords";

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
