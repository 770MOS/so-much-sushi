import type { Recommender } from "@/lib/searchTypes";
import type { Box } from "@/lib/resultsQuery";

// Favorites, Lists and one list (build step 5). Types for public.my_favorites,
// public.list_page and public.lists_overview, and small helpers the pages share.

// Who can see a list (decided 2026-11-12). Stored as private / friends / public.
export type Visibility = "private" | "friends" | "public";

export const LOCK_PATH =
  "M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2zM11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0M8 11v-4a4 4 0 1 1 8 0v4";
export const PEOPLE_PATH =
  "M9 7m-4 0a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M3 21v-2a4 4 0 0 1 4 -4h4a4 4 0 0 1 4 4v2M16 3.13a4 4 0 0 1 0 7.75M21 21v-2a4 4 0 0 0 -3 -3.85";
export const GLOBE_PATH =
  "M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0M3.6 9h16.8M3.6 15h16.8M11.5 3a17 17 0 0 0 0 18M12.5 3a17 17 0 0 1 0 18";
export const FLAG_PATH = "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7";

export const VISIBILITY: Record<Visibility, { label: string; d: string; help: string }> = {
  private: { label: "Just you", d: LOCK_PATH, help: "Only you can see it." },
  friends: { label: "Friends", d: PEOPLE_PATH, help: "Your friends can see it." },
  public: { label: "Public", d: GLOBE_PATH, help: "Anyone with the link can see it." },
};
export const VISIBILITY_ORDER: Visibility[] = ["private", "friends", "public"];

// The one-line note shown when someone picks Public (decided 2026-11-12).
export const PUBLIC_NOTE = "Anyone can find a public list, including on Google, along with your name.";

// A place on the Favorites page or in a list, with the same fields as a search result.
export type ListPlace = {
  id: string;
  name: string;
  address: string | null; // "street · town"
  street: string | null;
  city: string | null;
  state: string | null;
  lat: number;
  lng: number;
  status: string;
  categories: string[] | null;
  category_paths: string[] | null;
  recommended_by: Recommender[] | null;
  recommended_count: number;
  is_starred: boolean;
  is_want: boolean;
  added_at: string | null;
};

export type ListOwner = { name: string; handle: string | null };

export type ListPageData = {
  id: string;
  name: string;
  description: string | null;
  visibility: Visibility;
  is_default: boolean; // the ready-made Want to try
  is_owner: boolean;
  owner: ListOwner;
  places: ListPlace[];
};

// list_page's answer when the list exists but isn't shared with the viewer.
export type HiddenList = { id: string; hidden: true };

export type ListCardData = {
  id: string;
  name: string;
  visibility: Visibility;
  is_default: boolean;
  is_mine: boolean;
  owner_name: string | null;
  owner_handle: string | null;
  place_count: number;
  towns: string[];
  town_count: number;
  closest_miles: number | null;
  points: [number, number][];
  created_at: string;
};

// "under 0.1 mi", "0.4 mi", "12 mi".
export function formatMiles(miles: number): string {
  if (miles < 0.1) return "under 0.1 mi";
  if (miles < 10) return `${miles.toFixed(1)} mi`;
  return `${Math.round(miles).toLocaleString("en-US")} mi`;
}

// "Arlington, Washington" or "Arlington, Washington and 2 more".
export function townsLine(towns: string[], total: number): string {
  if (towns.length === 0) return "";
  const more = total - towns.length;
  return more > 0 ? `${towns.join(", ")} and ${more} more` : towns.join(", ");
}

// The map area that shows all these places, with a little room around them; a single place
// gets about half a mile each way.
export function boxForPlaces(points: { lat: number; lng: number }[]): Box | null {
  if (points.length === 0) return null;
  let west = Infinity, south = Infinity, east = -Infinity, north = -Infinity;
  for (const p of points) {
    west = Math.min(west, p.lng);
    east = Math.max(east, p.lng);
    south = Math.min(south, p.lat);
    north = Math.max(north, p.lat);
  }
  const minLat = 0.008; // about half a mile
  const minLng = minLat / Math.max(0.2, Math.cos((((south + north) / 2) * Math.PI) / 180));
  const padLat = Math.max((north - south) * 0.15, minLat - (north - south) / 2, 0);
  const padLng = Math.max((east - west) * 0.15, minLng - (east - west) / 2, 0);
  return { west: west - padLng, south: south - padLat, east: east + padLng, north: north + padLat };
}

export function placeWord(n: number) {
  return n === 1 ? "place" : "places";
}
