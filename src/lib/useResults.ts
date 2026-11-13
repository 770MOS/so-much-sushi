"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { setLastSearchCoords } from "@/lib/lastSearchCoords";
import { typeForPath } from "@/lib/entityTypes";
import type { Facets, SearchResult } from "@/lib/searchTypes";
import type { Only } from "@/lib/resultsQuery";

export type ResultsArgs = {
  lat: number;
  lng: number;
  r: number;
  kind: string | null;
  q: string;
  only: Only[];
  hidden: boolean;
};

// Runs the results page's search and its filter counts together whenever the search changes,
// and keeps the person's own marks (favorites, hidden places) in step as they change them.
// A slower answer to an older search never replaces a newer one.
export function useResults(userId: string | null, args: ResultsArgs | null) {
  const supabase = useMemo(() => createClient(), []);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [facets, setFacets] = useState<Facets | null>(null);
  // The search the results on screen answer, and its error if it failed. While the current
  // search is still out, the previous results stay on screen.
  const [answered, setAnswered] = useState<{ key: string; error: string | null } | null>(null);
  const [starredIds, setStarredIds] = useState<Set<string>>(new Set());
  const [hiddenIds, setHiddenIds] = useState<Set<string>>(new Set());
  const requestRef = useRef(0);

  const key = args ? JSON.stringify(args) : null;
  const loading = key !== null && answered?.key !== key;
  const error = answered && answered.key === key ? answered.error : null;

  useEffect(() => {
    if (!args) return;
    const requestId = ++requestRef.current;
    const kind = args.kind;
    const type = typeForPath(kind);
    const cuisine = kind && kind.includes(".") ? kind : null;
    const filters = {
      only_favorites: args.only.includes("favorites"),
      only_friends: args.only.includes("friends"),
      only_want: args.only.includes("want"),
      show_hidden: args.hidden,
    };
    const thisKey = key as string;
    Promise.all([
      supabase.rpc("search_places", {
        ref_lat: args.lat,
        ref_lng: args.lng,
        radius_miles: args.r,
        category_path: kind,
        name_query: args.q.trim() || null,
        ...filters,
      }),
      supabase.rpc("search_facets", {
        ref_lat: args.lat,
        ref_lng: args.lng,
        radius_miles: args.r,
        type_key: type,
        cuisine_path: cuisine,
        name_query: args.q.trim() || null,
        ...filters,
      }),
    ])
      .then(([placesRes, facetsRes]) => {
        if (requestId !== requestRef.current) return;
        if (placesRes.error) {
          setResults(null);
          setAnswered({ key: thisKey, error: "Something went wrong while searching. Please try again." });
          return;
        }
        const rows = (placesRes.data ?? []) as SearchResult[];
        setResults(rows);
        setStarredIds(new Set(rows.filter((r) => r.is_starred).map((r) => r.id)));
        setHiddenIds(new Set(rows.filter((r) => r.is_hidden).map((r) => r.id)));
        // The counts are a nicety: the results still show if they fail.
        setFacets(facetsRes.error ? null : (facetsRes.data as Facets));
        setLastSearchCoords({ lat: args.lat, lng: args.lng });
        setAnswered({ key: thisKey, error: null });
      })
      .catch(() => {
        if (requestId === requestRef.current) {
          setAnswered({ key: thisKey, error: "Something went wrong. Please check your connection and try again." });
        }
      });
    // args is captured through key: a new object with the same values is the same search.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, supabase]);

  async function toggleStar(entityId: string) {
    if (!userId) return;
    const on = starredIds.has(entityId);
    const { error: err } = on
      ? await supabase.from("stars").delete().eq("user_id", userId).eq("entity_id", entityId)
      : await supabase.from("stars").insert({ user_id: userId, entity_id: entityId });
    if (err) return;
    setStarredIds((prev) => {
      const next = new Set(prev);
      if (on) next.delete(entityId);
      else next.add(entityId);
      return next;
    });
    setFacets((f) => (f ? { ...f, favorites: Math.max(0, f.favorites + (on ? -1 : 1)) } : f));
  }

  async function toggleHide(entityId: string) {
    if (!userId) return;
    const on = hiddenIds.has(entityId);
    const { error: err } = on
      ? await supabase.from("hidden_entities").delete().eq("user_id", userId).eq("entity_id", entityId)
      : await supabase.from("hidden_entities").insert({ user_id: userId, entity_id: entityId });
    if (err) return;
    setHiddenIds((prev) => {
      const next = new Set(prev);
      if (on) next.delete(entityId);
      else next.add(entityId);
      return next;
    });
    setFacets((f) => (f ? { ...f, hidden: Math.max(0, f.hidden + (on ? -1 : 1)) } : f));
  }

  return { results, facets, loading, error, starredIds, hiddenIds, toggleStar, toggleHide };
}
