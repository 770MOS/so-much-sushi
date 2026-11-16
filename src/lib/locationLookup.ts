import { createClient } from "@/lib/supabase/client";
import { getLastSearchCoords, type Coords } from "@/lib/lastSearchCoords";

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

// Letters and digits only, single spaces: "St. Louis, MO" -> "st louis mo".
function plain(text: string) {
  return text.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

// A town or ZIP code typed without picking a suggestion: our own list's top suggestion
// (public.suggest_localities, nearby places first, then bigger ones), when it is the place
// typed: the same label ("saratoga springs ny"), the same name before any comma ("Saratoga
// Springs" or "Saratoga Springs, New York", whose state the list has already matched), or the
// same ZIP code. Anything else (a street address, a misspelling) is left to Nominatim.
async function fromOwnList(text: string, near: Coords | null): Promise<PickedLocation | null> {
  const point = near ?? getLastSearchCoords();
  try {
    const { data, error } = await createClient().rpc("suggest_localities", {
      query: text,
      near_lat: point?.lat ?? null,
      near_lng: point?.lng ?? null,
      max_results: 1,
    });
    const top = !error && Array.isArray(data) ? (data[0] as Record<string, unknown> | undefined) : undefined;
    if (!top || typeof top.label !== "string") return null;
    const label = top.label;
    const [typedName, ...typedRest] = text.split(",");
    const afterComma = plain(typedRest.join(" "));
    // A two-letter state after the comma has to be the suggestion's; a state written out
    // ("New York") was matched by the list itself.
    const stateOk = afterComma === "" || afterComma.length > 2 || afterComma === String(top.state ?? "").toLowerCase();
    const same = plain(text) === plain(label) || (plain(typedName) === plain(label.split(",")[0]) && stateOk);
    if (!same) return null;
    const found: PickedLocation = {
      label,
      lat: Number(top.lat),
      lng: Number(top.lng),
      city: (top.city as string | null) ?? null,
      state: (top.state as string | null) ?? null,
      radiusMiles: typeof top.radius_miles === "number" ? top.radius_miles : null,
    };
    return Number.isFinite(found.lat) && Number.isFinite(found.lng) ? found : null;
  } catch {
    return null;
  }
}

function asFound(pick: PickedLocation): FoundPlace {
  // (Before the land areas are loaded, a picked place opens like an address.)
  return pick.radiusMiles
    ? { lat: pick.lat, lng: pick.lng, radiusMiles: pick.radiusMiles, minPlaces: MIN_PLACES_PICKED }
    : { lat: pick.lat, lng: pick.lng, radiusMiles: 0, minPlaces: MIN_PLACES_OTHER };
}

// The place for whatever is in the location box: a picked suggestion; else, for a town or ZIP
// code typed out in full, our own list (see fromOwnList); else the text looked up with
// OpenStreetMap's Nominatim, as the box did before suggestions existed (street addresses and
// anything else not on the place-name list). `near` puts nearby towns first when a name is in
// several states. Null when nothing is found.
export async function geocodeLocationText(text: string, near: Coords | null = null): Promise<FoundPlace | null> {
  const typed = pickedLocationFor(text) ?? (await fromOwnList(text, near));
  if (typed) {
    rememberPickedLocation({ ...typed, label: text.trim() });
    return asFound(typed);
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
