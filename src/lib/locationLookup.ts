import type { Coords } from "@/lib/lastSearchCoords";

// A suggestion picked from the location box's dropdown (public.suggest_localities):
// the label shown in the box, its point, and its city and state.
export type PickedLocation = {
  label: string;
  lat: number;
  lng: number;
  city: string | null;
  state: string | null;
};

// Suggestions picked in this tab, by the label they put in the box. A search then uses the
// picked point directly instead of looking the text up again. Kept in memory only, like the
// rest of location search: nothing about where someone searched is stored.
const picked = new Map<string, PickedLocation>();

function key(text: string) {
  return text.trim().toLowerCase();
}

export function rememberPickedLocation(location: PickedLocation) {
  picked.set(key(location.label), location);
}

export function pickedLocationFor(text: string): PickedLocation | undefined {
  return picked.get(key(text));
}

const TIMEOUT_MS = 8000;

// Coordinates for whatever is in the location box: a picked suggestion's point, or else the
// text looked up with OpenStreetMap's Nominatim, as the box did before suggestions existed
// (street addresses and anything else not on the place-name list). Null when nothing is found.
export async function geocodeLocationText(text: string): Promise<Coords | null> {
  const pick = pickedLocationFor(text);
  if (pick) return { lat: pick.lat, lng: pick.lng };

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=${encodeURIComponent(text)}`,
      { signal: controller.signal }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) return null;
    return { lat: parseFloat(data[0].lat), lng: parseFloat(data[0].lon) };
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}
