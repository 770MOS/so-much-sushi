import type { Coords } from "@/lib/lastSearchCoords";

// A suggestion picked from the location box's dropdown (public.suggest_localities):
// the label shown in the box, its point, its city and state, and how wide the place is
// (the radius of a circle with its land area; null until the land areas are loaded).
export type PickedLocation = {
  label: string;
  lat: number;
  lng: number;
  city: string | null;
  state: string | null;
  radiusMiles: number | null;
};

// A place found for the Where box: its point, how far around it the map should open at least,
// and how many places the opening map should take in at least (see public.start_area).
export type FoundPlace = Coords & { radiusMiles: number; minPlaces: number };

// A picked town or ZIP code opens on the whole place, and on at least its 10 nearest places
// (a village may have none of its own). Anything else (a street address, a neighbourhood) opens
// on at least the nearest 50 places around it.
const MIN_PLACES_PICKED = 10;
const MIN_PLACES_OTHER = 50;

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
const MILES_PER_DEGREE_LAT = 69.0;

// Half the width or height of Nominatim's bounding box ([south, north, west, east]), in miles,
// whichever is larger: how big the place it found is. 0 for a point (a street address).
function boundingBoxRadius(bbox: unknown, lat: number): number {
  if (!Array.isArray(bbox) || bbox.length !== 4) return 0;
  const [south, north, west, east] = bbox.map((v) => parseFloat(String(v)));
  if (![south, north, west, east].every(Number.isFinite)) return 0;
  const halfHeight = ((north - south) / 2) * MILES_PER_DEGREE_LAT;
  const halfWidth = ((east - west) / 2) * MILES_PER_DEGREE_LAT * Math.cos((lat * Math.PI) / 180);
  return Math.max(0, halfHeight, halfWidth);
}

// The place for whatever is in the location box: a picked suggestion, or else the text looked
// up with OpenStreetMap's Nominatim, as the box did before suggestions existed (street
// addresses and anything else not on the place-name list). Null when nothing is found.
export async function geocodeLocationText(text: string): Promise<FoundPlace | null> {
  const pick = pickedLocationFor(text);
  // (Before the land areas are loaded, a picked place opens like an address.)
  if (pick) {
    return pick.radiusMiles
      ? { lat: pick.lat, lng: pick.lng, radiusMiles: pick.radiusMiles, minPlaces: MIN_PLACES_PICKED }
      : { lat: pick.lat, lng: pick.lng, radiusMiles: 0, minPlaces: MIN_PLACES_OTHER };
  }

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
    const lat = parseFloat(data[0].lat);
    const lng = parseFloat(data[0].lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
    return { lat, lng, radiusMiles: boundingBoxRadius(data[0].boundingbox, lat), minPlaces: MIN_PLACES_OTHER };
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}
