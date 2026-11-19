import type { SupabaseClient } from "@supabase/supabase-js";
import { boxAround, type Box } from "@/lib/resultsQuery";
import type { Coords } from "@/lib/lastSearchCoords";

// The map area a new search opens on (build step 3; replaces the distance menu): a square
// around the point, at least radiusMiles out (a picked town's own size), and wide enough to
// take in at least minPlaces places (public.start_area): a few blocks downtown, miles in the
// country. "Use my location" and the internet-address guess pass no radius and 50 places.
// A town's own size counts up to TOWN_RADIUS_CAP miles: big cities open on their busiest area,
// not all of it (20261119000000_big_cities.sql, which caps it in start_area too).
export const TOWN_RADIUS_CAP = 5;

export async function startArea(
  supabase: SupabaseClient,
  point: Coords,
  { radiusMiles = 0, minPlaces = 50 }: { radiusMiles?: number; minPlaces?: number } = {}
): Promise<Box> {
  const { data, error } = await supabase.rpc("start_area", {
    lat: point.lat,
    lng: point.lng,
    min_radius_miles: radiusMiles,
    min_places: minPlaces,
  });
  // If the database can't say, a town-sized square still gives a sensible start.
  const miles = !error && typeof data === "number" && data > 0 ? data : Math.max(Math.min(radiusMiles, TOWN_RADIUS_CAP), 2);
  return boxAround(point, miles);
}
