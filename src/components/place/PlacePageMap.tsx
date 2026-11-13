"use client";

import dynamic from "next/dynamic";
import { topLevelTypeForCategoryPaths } from "@/lib/entityTypes";
import type { PlaceDetail } from "@/lib/placeDetail";

const EntityMap = dynamic(() => import("@/components/EntityMap"), { ssr: false });

// The small map on a place's own page: the place's pin, nothing else.
export default function PlacePageMap({ place }: { place: PlaceDetail }) {
  return (
    <EntityMap
      entities={[
        {
          id: place.id,
          name: place.name,
          address: place.address ?? "",
          lat: place.lat,
          lng: place.lng,
          matchesFilter: true,
          isStarred: place.is_starred,
          recommendedCount: place.friends_count,
          isWant: place.is_want,
          status: place.status,
          entityType: topLevelTypeForCategoryPaths(place.categories.map((c) => c.path)),
        },
      ]}
      className="h-72 w-full overflow-hidden rounded-xl border border-line"
    />
  );
}
