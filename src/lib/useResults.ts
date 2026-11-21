"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { setLastSearchCoords } from "@/lib/lastSearchCoords";
import { typeForPath } from "@/lib/entityTypes";
import type { AreaCell, Facets, SearchResult } from "@/lib/searchTypes";
import { moreArg, type Box, type MoreFilters, type Only } from "@/lib/resultsQuery";
import { announceMark, useMarkChanges } from "@/lib/placeMarks";

export type ResultsArgs = {
  lat: number;
  lng: number;
  b: Box;
  kind: string | null;
  q: string;
  only: Only[];
  hidden: boolean;
  more: MoreFilters;
};

// The map's grid for bubbles with true counts: the area cut into this many columns (and rows
// of about the same size on the map). The map then groups neighbouring squares that would
// overlap at the current zoom.
const CELL_COLUMNS = 24;

// After this long, a search still out is called slow: "Still searching…".
const SLOW_MS = 3000;

// What the page says when a search fails. "slow": the database gave up at its time limit
// (8 seconds), which a first search over a large, busy area can still reach.
export type SearchError = { message: string; slow: boolean };

function errorFor(err: { message?: string; code?: string } | null | undefined): SearchError {
  const message = err?.message ?? "";
  if (message.includes("too large")) {
    return { message: "That area is too large to search. Zoom the map in and search again.", slow: false };
  }
  if (err?.code === "57014" || message.includes("statement timeout")) {
    return {
      message: "This search took too long. Zoom the map in, or pick a kind, and try again.",
      slow: true,
    };
  }
  return { message: "Something went wrong while searching. Please try again.", slow: false };
}

// Runs the results page's search and its filter counts together whenever the search changes,
// and keeps the person's own marks (favorites, hidden places) in step as they change them.
// When more places match than the list holds (1,000), and the map is showing (wantCells), it
// also counts every match on a grid for the map's bubbles. A slower answer to an older search
// never replaces a newer one.
export function useResults(userId: string | null, args: ResultsArgs | null, wantCells = false) {
  const supabase = useMemo(() => createClient(), []);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [facets, setFacets] = useState<Facets | null>(null);
  // The search the results on screen answer, and its error if it failed. While the current
  // search is still out, the previous results stay on screen.
  const [answered, setAnswered] = useState<{ key: string; error: SearchError | null } | null>(null);
  // Try again: the same search once more (bumping this runs it again).
  const [attempt, setAttempt] = useState(0);
  // The search that has been out for more than SLOW_MS: the page says it's still working.
  const [slowKey, setSlowKey] = useState<string | null>(null);
  const [cells, setCells] = useState<{ key: string; cells: AreaCell[] } | null>(null);
  const [starredIds, setStarredIds] = useState<Set<string>>(new Set());
  const [hiddenIds, setHiddenIds] = useState<Set<string>>(new Set());
  const requestRef = useRef(0);
  const cellsRequestRef = useRef(0);

  const key = args ? JSON.stringify(args) : null;
  const loading = key !== null && answered?.key !== key;
  const slow = loading && slowKey === key;
  const error = answered && answered.key === key ? answered.error : null;
  const total = results && results.length > 0 ? (results[0].total_count ?? results.length) : 0;
  const capped = !loading && results !== null && results.length >= 1000 && total > results.length;

  function filters(a: ResultsArgs) {
    return {
      category_path: a.kind,
      name_query: a.q.trim() || null,
      only_favorites: a.only.includes("favorites"),
      only_friends: a.only.includes("friends"),
      only_want: a.only.includes("want"),
      show_hidden: a.hidden,
      more: moreArg(a.more),
    };
  }

  useEffect(() => {
    if (!args) return;
    const requestId = ++requestRef.current;
    const { category_path, ...rest } = filters(args);
    const type = typeForPath(category_path);
    const cuisine = category_path && category_path.includes(".") ? category_path : null;
    const box = { west: args.b.west, south: args.b.south, east: args.b.east, north: args.b.north };
    const thisKey = key as string;
    const slowTimer = setTimeout(() => {
      if (requestId === requestRef.current) setSlowKey(thisKey);
    }, SLOW_MS);
    Promise.all([
      supabase.rpc("search_area", { ref_lat: args.lat, ref_lng: args.lng, ...box, category_path, ...rest }),
      supabase.rpc("area_facets", { ...box, type_key: type, cuisine_path: cuisine, ...rest }),
    ])
      .then(([placesRes, facetsRes]) => {
        if (requestId !== requestRef.current) return;
        if (placesRes.error) {
          setResults(null);
          // The counts answer the new search (or none), not the last one.
          setFacets(facetsRes.error ? null : (facetsRes.data as Facets));
          setAnswered({ key: thisKey, error: errorFor(placesRes.error) });
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
          setAnswered({
            key: thisKey,
            error: { message: "Something went wrong. Please check your connection and try again.", slow: false },
          });
        }
      });
    return () => clearTimeout(slowTimer);
    // args is captured through key: a new object with the same values is the same search.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, supabase, attempt]);

  // The grid counts, only once the list turns out to be capped and the map wants them.
  const needCells = capped && wantCells && key !== null && cells?.key !== key;
  useEffect(() => {
    if (!needCells || !args) return;
    const requestId = ++cellsRequestRef.current;
    const thisKey = key as string;
    const { west, south, east, north } = args.b;
    const cellLng = (east - west) / CELL_COLUMNS;
    const cellLat = cellLng * Math.cos((((south + north) / 2) * Math.PI) / 180);
    supabase
      .rpc("area_cells", { west, south, east, north, cell_lng: cellLng, cell_lat: cellLat, ...filters(args) })
      .then(({ data, error: err }) => {
        if (requestId !== cellsRequestRef.current) return;
        // Without them the map still shows the nearest 1,000.
        setCells({ key: thisKey, cells: err || !data ? [] : (data as AreaCell[]) });
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [needCells, key, supabase]);

  // A heart, Want to try or hide changed in a place panel: the list and map follow.
  useMarkChanges((change) => {
    if (change.from === "results") return;
    if (change.hidden !== undefined && hiddenIds.has(change.id) !== change.hidden) {
      const on = change.hidden;
      setHiddenIds((prev) => {
        const next = new Set(prev);
        if (on) next.add(change.id);
        else next.delete(change.id);
        return next;
      });
      // Counted only for places in this search.
      if (results?.some((r) => r.id === change.id)) {
        setFacets((f) => (f ? { ...f, hidden: Math.max(0, f.hidden + (on ? 1 : -1)) } : f));
      }
    }
    if (change.starred !== undefined && starredIds.has(change.id) !== change.starred) {
      const on = change.starred;
      setStarredIds((prev) => {
        const next = new Set(prev);
        if (on) next.add(change.id);
        else next.delete(change.id);
        return next;
      });
      setFacets((f) => (f ? { ...f, favorites: Math.max(0, f.favorites + (on ? 1 : -1)) } : f));
    }
    if (change.want !== undefined) {
      const want = change.want;
      setResults((rows) => rows?.map((r) => (r.id === change.id ? { ...r, is_want: want } : r)) ?? rows);
    }
    if (change.moved) {
      const { lat, lng } = change.moved;
      setResults((rows) => rows?.map((r) => (r.id === change.id ? { ...r, lat, lng } : r)) ?? rows);
    }
  });

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
    announceMark({ id: entityId, starred: !on, from: "results" });
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
    announceMark({ id: entityId, hidden: !on, from: "results" });
  }

  // Runs the same search again (after an error): back to "Searching…" until it answers.
  function retry() {
    setAnswered(null);
    setAttempt((n) => n + 1);
  }

  return {
    results,
    facets,
    loading,
    slow,
    error,
    retry,
    total,
    capped,
    // The grid counts for the search on screen, or null (not capped, not asked for, or not back yet).
    cells: capped && cells?.key === key ? cells.cells : null,
    starredIds,
    hiddenIds,
    toggleStar,
    toggleHide,
  };
}
