import type { Coords } from "@/lib/lastSearchCoords";

const TIMEOUT_MS = 5000;

// zoom=14 asks Nominatim for neighbourhood/suburb-level detail rather than
// the building/street level its default (zoom=18) would return - we want
// "Clarendon, Arlington, VA", not a full street address off raw GPS.
const REVERSE_GEOCODE_ZOOM = 14;

type NominatimAddress = {
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

// Best-effort: returns a short human-readable place name for the given
// coordinates, or null if the request fails, times out, or the response has
// no usable fields. Callers should fall back to their own default on null -
// this never throws.
export async function reverseGeocode(coords: Coords): Promise<string | null> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${coords.lat}&lon=${coords.lng}&zoom=${REVERSE_GEOCODE_ZOOM}&addressdetails=1`,
      { signal: controller.signal }
    );
    if (!res.ok) return null;

    const data = await res.json();
    const address: NominatimAddress | undefined = data?.address;
    if (!address) return null;

    const area = address.neighbourhood || address.suburb || address.quarter || address.hamlet;
    const city = address.city || address.town || address.village || address.municipality || address.county;
    const state = address.state;

    const parts = [area, city, state].filter(
      (p): p is string => typeof p === "string" && p.trim().length > 0
    );
    if (parts.length === 0) return null;

    return parts.join(", ");
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
}
