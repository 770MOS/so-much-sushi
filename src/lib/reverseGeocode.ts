import type { Coords } from "@/lib/lastSearchCoords";

const TIMEOUT_MS = 5000;

// zoom=14 asks Nominatim for neighbourhood/suburb-level detail rather than
// the building/street level its default (zoom=18) would return - we want
// "Clarendon, Arlington, VA", not a full street address off raw GPS.
const REVERSE_GEOCODE_ZOOM = 14;

export type NominatimAddress = {
  neighbourhood?: string;
  suburb?: string;
  quarter?: string;
  hamlet?: string;
  city?: string;
  town?: string;
  village?: string;
  municipality?: string;
  county?: string;
  state?: string;
};

export type CityState = { city: string | null; state: string | null };

// Nominatim returns full US state names ("Virginia"), not the two-letter
// abbreviation ("VA") this app displays/stores everywhere - normalize here
// so it's consistent regardless of which geocode path produced it.
const US_STATE_ABBREVIATIONS: Record<string, string> = {
  alabama: "AL", alaska: "AK", arizona: "AZ", arkansas: "AR", california: "CA",
  colorado: "CO", connecticut: "CT", delaware: "DE", florida: "FL", georgia: "GA",
  hawaii: "HI", idaho: "ID", illinois: "IL", indiana: "IN", iowa: "IA",
  kansas: "KS", kentucky: "KY", louisiana: "LA", maine: "ME", maryland: "MD",
  massachusetts: "MA", michigan: "MI", minnesota: "MN", mississippi: "MS", missouri: "MO",
  montana: "MT", nebraska: "NE", nevada: "NV", "new hampshire": "NH", "new jersey": "NJ",
  "new mexico": "NM", "new york": "NY", "north carolina": "NC", "north dakota": "ND", ohio: "OH",
  oklahoma: "OK", oregon: "OR", pennsylvania: "PA", "rhode island": "RI", "south carolina": "SC",
  "south dakota": "SD", tennessee: "TN", texas: "TX", utah: "UT", vermont: "VT",
  virginia: "VA", washington: "WA", "west virginia": "WV", wisconsin: "WI", wyoming: "WY",
  "district of columbia": "DC",
};

function abbreviateState(state: string): string {
  return US_STATE_ABBREVIATIONS[state.trim().toLowerCase()] ?? state;
}

// Shared city/state extraction, used by both the reverse (coords -> label)
// and forward (typed text -> label) geocode paths - same fallback chain
// either way, so "Arlington, VA" means the same thing regardless of which
// direction produced it.
export function extractCityState(address: NominatimAddress | undefined | null): CityState {
  if (!address) return { city: null, state: null };
  const city = address.city || address.town || address.village || address.municipality || address.county || null;
  const state = address.state ? abbreviateState(address.state) : null;
  return { city, state };
}

async function fetchWithTimeout(url: string): Promise<Response | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    return res.ok ? res : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}

// Best-effort: returns a short human-readable place name for the given
// coordinates, or null if the request fails, times out, or the response has
// no usable fields. Callers should fall back to their own default on null -
// this never throws.
export async function reverseGeocode(coords: Coords): Promise<string | null> {
  const res = await fetchWithTimeout(
    `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${coords.lat}&lon=${coords.lng}&zoom=${REVERSE_GEOCODE_ZOOM}&addressdetails=1`
  );
  if (!res) return null;

  const data = await res.json();
  const address: NominatimAddress | undefined = data?.address;
  if (!address) return null;

  const area = address.neighbourhood || address.suburb || address.quarter || address.hamlet;
  const { city, state } = extractCityState(address);

  const parts = [area, city, state].filter(
    (p): p is string => typeof p === "string" && p.trim().length > 0
  );
  if (parts.length === 0) return null;

  return parts.join(", ");
}

// Forward direction: "Arlington, VA" -> coordinates. Used to turn a
// signed-in user's saved home_city/home_state (text only - there's no
// stored home lat/lng) into coordinates a search can actually run from.
export async function geocodeCityState(city: string | null, state: string | null): Promise<Coords | null> {
  const query = [city, state].filter((p): p is string => Boolean(p && p.trim())).join(", ");
  if (!query) return null;

  const res = await fetchWithTimeout(
    `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=${encodeURIComponent(query)}`
  );
  if (!res) return null;

  const data = await res.json();
  if (!Array.isArray(data) || data.length === 0) return null;

  const lat = parseFloat(data[0].lat);
  const lng = parseFloat(data[0].lon);
  if (Number.isNaN(lat) || Number.isNaN(lng)) return null;

  return { lat, lng };
}

// Same reverse endpoint as reverseGeocode(), but returns structured
// city/state instead of a combined display label - for storing a home
// location, where we want "Arlington"/"VA" as separate values, not a
// pre-joined string.
export async function reverseGeocodeCityState(coords: Coords): Promise<CityState | null> {
  const res = await fetchWithTimeout(
    `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${coords.lat}&lon=${coords.lng}&zoom=${REVERSE_GEOCODE_ZOOM}&addressdetails=1`
  );
  if (!res) return null;

  const data = await res.json();
  const address: NominatimAddress | undefined = data?.address;
  if (!address) return null;

  return extractCityState(address);
}
