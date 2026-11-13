// A place as the panel, the phone sheet and the full place page show it (public.place_detail).
// Shared by server and browser code: types and small display helpers only.

import { TYPE_OPTIONS, typeForPath } from "@/lib/entityTypes";
import type { Recommender } from "@/lib/searchTypes";

export type PlaceDetail = {
  id: string;
  name: string;
  address: string | null; // one line: "2909 Wilson Blvd, Arlington, VA 22201"
  street: string | null;
  city: string | null;
  state: string | null;
  postal_code: string | null;
  phone: string | null;
  website: string | null;
  hours: string | null;
  status: string;
  lat: number;
  lng: number;
  categories: { name: string; path: string }[]; // main category first
  is_starred: boolean;
  is_want: boolean;
  lists: { id: string; name: string }[]; // the viewer's other lists it's on
  friends: Recommender[]; // up to three, earliest first
  friends_count: number;
  sources: string[];
};

// "Italian · Restaurants": the finest kind (when there is one) and the type.
export function placeKinds(place: Pick<PlaceDetail, "categories">): { cuisine: { name: string; path: string } | null; type: { key: string; label: string } | null } {
  const main = place.categories[0];
  const typeKey = typeForPath(main?.path);
  const type = typeKey ? { key: typeKey, label: TYPE_OPTIONS.find((t) => t.key === typeKey)!.label } : null;
  const finer = place.categories.slice(1).sort((a, b) => b.path.split(".").length - a.path.split(".").length)[0] ?? null;
  return { cuisine: finer, type };
}

// The address on two lines, as in the panel: street, then town, state and ZIP.
export function addressLines(place: Pick<PlaceDetail, "street" | "city" | "state" | "postal_code" | "address">): string[] {
  const zip = place.postal_code?.match(/^\s*(\d{5})/)?.[1] ?? place.postal_code;
  const town = [place.city, [place.state, zip].filter(Boolean).join(" ")].filter(Boolean).join(", ");
  const lines = [place.street, town].filter((l): l is string => Boolean(l && l.trim()));
  return lines.length ? lines : place.address ? [place.address] : [];
}

// "Details from ...": who the place's details come from, by source.
const SOURCE_NAMES: Record<string, string> = {
  overture_places: "Overture Maps Foundation",
  alltheplaces: "All the Places",
  venue_website: "the place's own website",
  manual_research: "So Much Sushi",
  user_report: "people who use So Much Sushi",
};

export function sourcesLine(codes: string[]): string {
  const names = [...new Set(codes.map((c) => SOURCE_NAMES[c]).filter(Boolean))];
  if (names.length === 0) return "Added by So Much Sushi.";
  const joined = names.length === 1 ? names[0] : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  return `Details from ${joined}.`;
}

// Miles between two points, for "0.2 mi" when the panel opens from a search.
export function milesBetween(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 3958.8 * 2 * Math.asin(Math.sqrt(h));
}

// Directions in the person's choice of maps app (decided 2026-11-10: offer both, they pick).
export function directionsLinks(place: Pick<PlaceDetail, "name" | "address" | "lat" | "lng">) {
  const where = place.address ? `${place.name}, ${place.address}` : `${place.lat},${place.lng}`;
  return {
    apple: `https://maps.apple.com/?daddr=${place.lat},${place.lng}&q=${encodeURIComponent(place.name)}`,
    google: `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(where)}`,
  };
}
