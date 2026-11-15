// Fixing map pins (2026-11-15): what the forms ask and how the answers are shown.

export type PinHow = "was_there" | "business" | "other";
export type PinMethod = "map" | "gps";

// How someone knows where the place is. Not from another map or app: map services' terms
// forbid making data from their maps, and our pins stay ours to share.
export const PIN_HOW: { key: PinHow; label: string }[] = [
  { key: "was_there", label: "I’ve been there" },
  { key: "business", label: "The business’s own website or sign" },
  { key: "other", label: "Something else (say how in the note)" },
];

export const PIN_HOW_SHORT: Record<PinHow, string> = {
  was_there: "Was there",
  business: "Business’s website or sign",
  other: "Other",
};

export const NOT_FROM_MAPS = "Please don’t place it from Google Maps, Yelp or another map or app.";

// The box a member ticks so we may use their correction. Plain words for now; the site's terms
// are to carry the same permission before testers join.
export const PIN_AGREEMENT = "So Much Sushi may use, change and share this correction, including with other services.";

// A phone location better than this is used as it is; a rougher one is a starting point to drag.
export const GOOD_GPS_METERS = 10;

// How a pin was placed, in a few words: "Dragged on the map", "Phone location, within 6 m".
export function placedBy(method: string | null | undefined, accuracy: number | null | undefined): string {
  if (method === "gps") return accuracy != null ? `Phone location, within ${Math.round(accuracy)} m` : "Phone location";
  return "Placed on the map";
}

export function metersText(m: number): string {
  return m < 1000 ? `${Math.round(m)} m` : `${(m / 1000).toFixed(1)} km`;
}

// Straight-line distance in meters (close enough at these distances).
export function metersBetween(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const rad = Math.PI / 180;
  const x = (b.lng - a.lng) * rad * Math.cos(((a.lat + b.lat) / 2) * rad);
  const y = (b.lat - a.lat) * rad;
  return Math.sqrt(x * x + y * y) * 6371000;
}

export type PinPlacement = { lat: number; lng: number; method: PinMethod; accuracy: number | null };
