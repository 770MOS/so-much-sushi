"use client";

import { useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import StatusBadge from "@/components/StatusBadge";
import WantToGoButton from "@/components/WantToGoButton";
import ShareButton from "@/components/ShareButton";
import { StarIcon } from "@/components/icons";
import type { MapMarkerEntity } from "@/components/EntityMap";
import { topLevelTypeForCategoryPaths } from "@/lib/entityTypes";

const EntityMap = dynamic(() => import("@/components/EntityMap"), { ssr: false });

export type EntityDetail = {
  id: string;
  name: string;
  address: string;
  phone: string | null;
  website: string | null;
  // jsonb - never populated yet (see supabase/get_entity_detail.sql), but
  // when it is, OSM's opening_hours tag is a plain string, not a structured
  // object - handled as a string, with attributes.opening_hours as a
  // fallback shape in case a future backfill lands it there instead.
  hours: string | null;
  attributes: { opening_hours?: string } | null;
  status: string;
  lat: number;
  lng: number;
  is_starred: boolean;
  categories: string[] | null;
  category_paths: string[] | null;
};

function hoursDisplay(entity: EntityDetail): string {
  const raw = entity.hours || entity.attributes?.opening_hours;
  if (typeof raw === "string" && raw.trim()) return raw;
  return entity.website ? "Hours not listed — visit their website" : "Hours not listed";
}

export default function VenueDetail({ entity }: { entity: EntityDetail }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [user, setUser] = useState<User | null>(null);
  const [isStarred, setIsStarred] = useState(entity.is_starred);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  async function toggleStar() {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    if (isStarred) {
      const { error } = await supabase
        .from("stars")
        .delete()
        .eq("user_id", user.id)
        .eq("entity_id", entity.id);
      if (!error) setIsStarred(false);
    } else {
      const { error } = await supabase
        .from("stars")
        .insert({ user_id: user.id, entity_id: entity.id });
      if (!error) setIsStarred(true);
    }
  }

  const mapEntity: MapMarkerEntity = {
    id: entity.id,
    name: entity.name,
    address: entity.address,
    lat: entity.lat,
    lng: entity.lng,
    matchesFilter: true,
    isStarred,
    recommendedCount: 0,
    status: entity.status,
    entityType: topLevelTypeForCategoryPaths(entity.category_paths),
  };

  return (
    <div className="flex flex-col gap-6 px-6 py-8">
      <div className="flex flex-col gap-2">
        <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">{entity.name}</h1>
        {entity.categories && entity.categories.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {entity.categories.map((c) => (
              <span
                key={c}
                className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs text-zinc-600 dark:bg-zinc-900 dark:text-zinc-400"
              >
                {c}
              </span>
            ))}
          </div>
        )}
        <StatusBadge status={entity.status} />
      </div>

      <div className="flex flex-col gap-1 text-sm text-zinc-700 dark:text-zinc-300">
        <p>{entity.address}</p>
        {entity.phone && (
          <a href={`tel:${entity.phone}`} className="w-fit text-primary hover:underline">
            {entity.phone}
          </a>
        )}
        {entity.website && (
          <a
            href={entity.website}
            target="_blank"
            rel="noopener noreferrer"
            className="w-fit text-primary hover:underline"
          >
            Visit website
          </a>
        )}
        <p className="text-zinc-500 dark:text-zinc-400">{hoursDisplay(entity)}</p>
      </div>

      <EntityMap
        entities={[mapEntity]}
        onToggleStar={toggleStar}
        className="h-64 w-full rounded-lg"
      />

      <div className="flex items-center gap-3 border-t border-zinc-200 pt-4 dark:border-zinc-800">
        <button
          type="button"
          onClick={toggleStar}
          aria-pressed={isStarred}
          aria-label={isStarred ? "Unstar" : "Star"}
          className="flex items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
        >
          <StarIcon filled={isStarred} />
          {isStarred ? "Starred" : "Star"}
        </button>
        <WantToGoButton userId={user?.id ?? null} entityId={entity.id} />
        <ShareButton path={`/venue/${entity.id}`} title={entity.name} />
      </div>
    </div>
  );
}
