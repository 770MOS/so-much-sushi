import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { PlaceDetail } from "@/lib/placeDetail";

// One place for the panel or the full page (public.place_detail), as the signed-in person
// sees it. Cached per request, so the page and its metadata share one call. Null when there's
// no such place.
export const getPlaceDetail = cache(async (id: string): Promise<PlaceDetail | null> => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("place_detail", { place_id: id });
  if (error || !data) return null;
  return data as PlaceDetail;
});
