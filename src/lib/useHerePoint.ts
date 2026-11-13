"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { getLastSearchArea } from "@/lib/lastSearchCoords";
import { geocodeLocationText } from "@/lib/locationLookup";
import { fetchIpArea } from "@/lib/ipArea";

// Where "nearest to you" is measured from on the Favorites and Lists pages, in the same order
// the results page opens on: this session's last search, else a member's home area, else the
// area guessed from the internet connection (nothing stored). No location is asked for.
export type HerePoint = { lat: number; lng: number; label: string };

let found: { userId: string | null; point: HerePoint | null } | null = null;

async function lookUp(userId: string | null): Promise<HerePoint | null> {
  const last = getLastSearchArea();
  if (last) return { lat: last.lat, lng: last.lng, label: last.where };
  if (userId) {
    const { data } = await createClient().rpc("get_my_home_location");
    const row = data?.[0];
    const home = [row?.home_city, row?.home_state].filter(Boolean).join(", ");
    const place = home ? await geocodeLocationText(home) : null;
    if (place) return { lat: place.lat, lng: place.lng, label: home };
  }
  const ip = await fetchIpArea();
  return ip ? { lat: ip.lat, lng: ip.lng, label: ip.label } : null;
}

// undefined while it's being worked out (or before sign-in is known), then a point or null.
export function useHerePoint(userId: string | null | undefined): HerePoint | null | undefined {
  const [point, setPoint] = useState<{ userId: string | null; value: HerePoint | null } | null>(null);

  useEffect(() => {
    if (userId === undefined) return;
    let cancelled = false;
    (async () => {
      await Promise.resolve();
      // A search made since the last look moves the point.
      const last = getLastSearchArea();
      let value: HerePoint | null;
      if (last) value = { lat: last.lat, lng: last.lng, label: last.where };
      else if (found && found.userId === userId) value = found.point;
      else {
        value = await lookUp(userId);
        found = { userId, point: value };
      }
      if (!cancelled) setPoint({ userId, value });
    })();
    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (userId === undefined || !point || point.userId !== userId) return undefined;
  return point.value;
}
