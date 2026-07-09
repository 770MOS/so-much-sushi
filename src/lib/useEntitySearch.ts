"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import { setLastSearchCoords } from "@/lib/lastSearchCoords";
import type { MapMarkerEntity } from "@/components/EntityMap";
import type { SearchResult, SortMode, ViewMode } from "@/lib/searchTypes";

type RunSearchOptions = {
  lat: number;
  lng: number;
  radiusMiles: number;
  categoryPath?: string | null;
  recommendedOnly?: boolean;
  showHidden?: boolean;
  starredOnly?: boolean;
};

export function useEntitySearch(user: User | null) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [sortMode, setSortMode] = useState<SortMode>("nearest");
  const [viewMode, setViewMode] = useState<ViewMode>("list");
  const [starredIds, setStarredIds] = useState<Set<string>>(new Set());
  const [hiddenIds, setHiddenIds] = useState<Set<string>>(new Set());

  const sortedResults = useMemo(() => {
    if (!results) return [];
    if (sortMode === "az") {
      return [...results].sort((a, b) => a.name.localeCompare(b.name));
    }
    return results;
  }, [results, sortMode]);

  const mapMarkerEntities: MapMarkerEntity[] = useMemo(() => {
    return sortedResults.map((r) => ({
      id: r.id,
      name: r.name,
      address: r.address,
      lat: r.lat,
      lng: r.lng,
      matchesFilter: true,
      isStarred: starredIds.has(r.id),
      recommendedCount: r.recommended_count,
      status: r.status,
    }));
  }, [sortedResults, starredIds]);

  async function runSearch(opts: RunSearchOptions) {
    const { data, error: rpcError } = await supabase.rpc("search_entities", {
      ref_lat: opts.lat,
      ref_lng: opts.lng,
      radius_miles: opts.radiusMiles,
      category_path: opts.categoryPath || null,
      recommended_only: opts.recommendedOnly ?? false,
      show_hidden: opts.showHidden ?? false,
      starred_only: opts.starredOnly ?? false,
    });

    if (rpcError) {
      setError("Something went wrong while searching. Please try again.");
      return;
    }

    setLastSearchCoords({ lat: opts.lat, lng: opts.lng });

    const searchResults: SearchResult[] = data ?? [];
    setResults(searchResults);
    setStarredIds(new Set(searchResults.filter((r) => r.is_starred).map((r) => r.id)));
    setHiddenIds(new Set(searchResults.filter((r) => r.is_hidden).map((r) => r.id)));
  }

  async function toggleStar(entityId: string) {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    const isStarred = starredIds.has(entityId);

    if (isStarred) {
      const { error: deleteError } = await supabase
        .from("stars")
        .delete()
        .eq("user_id", user.id)
        .eq("entity_id", entityId);
      if (!deleteError) {
        setStarredIds((prev) => {
          const next = new Set(prev);
          next.delete(entityId);
          return next;
        });
      }
    } else {
      const { error: insertError } = await supabase
        .from("stars")
        .insert({ user_id: user.id, entity_id: entityId });
      if (!insertError) {
        setStarredIds((prev) => new Set(prev).add(entityId));
      }
    }
  }

  async function toggleHide(entityId: string) {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    const isHidden = hiddenIds.has(entityId);

    if (isHidden) {
      const { error: deleteError } = await supabase
        .from("hidden_entities")
        .delete()
        .eq("user_id", user.id)
        .eq("entity_id", entityId);
      if (!deleteError) {
        setHiddenIds((prev) => {
          const next = new Set(prev);
          next.delete(entityId);
          return next;
        });
      }
    } else {
      const { error: insertError } = await supabase
        .from("hidden_entities")
        .insert({ user_id: user.id, entity_id: entityId });
      if (!insertError) {
        setHiddenIds((prev) => new Set(prev).add(entityId));
      }
    }
  }

  return {
    loading,
    setLoading,
    error,
    setError,
    results,
    setResults,
    sortedResults,
    mapMarkerEntities,
    sortMode,
    setSortMode,
    viewMode,
    setViewMode,
    starredIds,
    hiddenIds,
    runSearch,
    toggleStar,
    toggleHide,
  };
}
