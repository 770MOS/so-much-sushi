"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import dynamic from "next/dynamic";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { MapBounds, MapMarkerEntity } from "./StarredMap";

const StarredMap = dynamic(() => import("./StarredMap"), { ssr: false });

type StarredRow = {
  id: string;
  name: string;
  address: string;
  city: string | null;
  state: string | null;
  lat: number;
  lng: number;
  type_name: string;
  cuisine_name: string;
};

type StarredEntity = {
  id: string;
  name: string;
  address: string;
  city: string | null;
  state: string | null;
  lat: number;
  lng: number;
  tags: { type_name: string; cuisine_name: string }[];
};

type Tab = "map" | "browse";

function locationKey(city: string | null, state: string | null) {
  if (!city && !state) return null;
  return [city, state].filter(Boolean).join(", ");
}

function tabButtonClass(active: boolean) {
  return `rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
    active
      ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"
      : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
  }`;
}

const selectClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-950 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

export default function Profile() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [rows, setRows] = useState<StarredRow[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("map");

  const [mapType, setMapType] = useState("");
  const [mapCuisine, setMapCuisine] = useState("");
  const [jumpToKey, setJumpToKey] = useState("");
  const [jumpTarget, setJumpTarget] = useState<{ lat: number; lng: number } | null>(null);
  const [mapBounds, setMapBounds] = useState<MapBounds | null>(null);

  const [browseCity, setBrowseCity] = useState("");
  const [browseType, setBrowseType] = useState("");
  const [browseCuisine, setBrowseCuisine] = useState("");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (user === null) {
      router.replace("/sign-in");
    }
  }, [user, router]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    async function loadStarred() {
      const { data, error } = await supabase.rpc("get_my_starred_entities");
      if (cancelled) return;
      if (error) {
        setLoadError("Something went wrong loading your starred places.");
        return;
      }
      setRows(data ?? []);
    }
    loadStarred();
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  const entities = useMemo<StarredEntity[]>(() => {
    if (!rows) return [];
    const byId = new Map<string, StarredEntity>();
    for (const r of rows) {
      let e = byId.get(r.id);
      if (!e) {
        e = {
          id: r.id,
          name: r.name,
          address: r.address,
          city: r.city,
          state: r.state,
          lat: r.lat,
          lng: r.lng,
          tags: [],
        };
        byId.set(r.id, e);
      }
      e.tags.push({ type_name: r.type_name, cuisine_name: r.cuisine_name });
    }
    return [...byId.values()];
  }, [rows]);

  function entityMatchesTypeCuisine(e: StarredEntity, type: string, cuisine: string) {
    if (!type) return true;
    return e.tags.some((t) => t.type_name === type && (!cuisine || t.cuisine_name === cuisine));
  }

  // --- Map tab ---

  const mapTypeOptions = useMemo(() => {
    return [...new Set((rows ?? []).map((r) => r.type_name))].sort();
  }, [rows]);

  const mapCuisineOptions = useMemo(() => {
    const filtered = (rows ?? []).filter((r) => !mapType || r.type_name === mapType);
    return [...new Set(filtered.map((r) => r.cuisine_name))].sort();
  }, [rows, mapType]);

  const jumpToOptions = useMemo(() => {
    const keys = new Set<string>();
    for (const e of entities) {
      const key = locationKey(e.city, e.state);
      if (key) keys.add(key);
    }
    return [...keys].sort();
  }, [entities]);

  const mapMarkerEntities: MapMarkerEntity[] = useMemo(() => {
    return entities.map((e) => ({
      id: e.id,
      name: e.name,
      address: e.address,
      lat: e.lat,
      lng: e.lng,
      matchesFilter: entityMatchesTypeCuisine(e, mapType, mapCuisine),
    }));
  }, [entities, mapType, mapCuisine]);

  const mapViewportList = useMemo(() => {
    return entities.filter((e) => {
      if (!entityMatchesTypeCuisine(e, mapType, mapCuisine)) return false;
      if (!mapBounds) return true;
      return (
        e.lat <= mapBounds.north &&
        e.lat >= mapBounds.south &&
        e.lng <= mapBounds.east &&
        e.lng >= mapBounds.west
      );
    });
  }, [entities, mapType, mapCuisine, mapBounds]);

  const handleBoundsChange = useCallback((bounds: MapBounds) => {
    setMapBounds(bounds);
  }, []);

  function handleJumpTo(key: string) {
    setJumpToKey(key);
    if (!key) {
      setJumpTarget(null);
      return;
    }
    const match = entities.find((e) => locationKey(e.city, e.state) === key);
    if (match) setJumpTarget({ lat: match.lat, lng: match.lng });
  }

  // --- Browse tab ---

  const browseCityOptions = useMemo(() => {
    const keys = new Set<string>();
    for (const r of rows ?? []) {
      const key = locationKey(r.city, r.state);
      if (key) keys.add(key);
    }
    return [...keys].sort();
  }, [rows]);

  const browseTypeOptions = useMemo(() => {
    const filtered = (rows ?? []).filter(
      (r) => !browseCity || locationKey(r.city, r.state) === browseCity
    );
    return [...new Set(filtered.map((r) => r.type_name))].sort();
  }, [rows, browseCity]);

  const browseCuisineOptions = useMemo(() => {
    const filtered = (rows ?? []).filter((r) => {
      if (browseCity && locationKey(r.city, r.state) !== browseCity) return false;
      if (browseType && r.type_name !== browseType) return false;
      return true;
    });
    return [...new Set(filtered.map((r) => r.cuisine_name))].sort();
  }, [rows, browseCity, browseType]);

  const browseList = useMemo(() => {
    const filteredRows = (rows ?? []).filter((r) => {
      if (browseCity && locationKey(r.city, r.state) !== browseCity) return false;
      if (browseType && r.type_name !== browseType) return false;
      if (browseCuisine && r.cuisine_name !== browseCuisine) return false;
      return true;
    });

    const byId = new Map<
      string,
      { id: string; name: string; address: string; tags: Set<string> }
    >();
    for (const r of filteredRows) {
      let entry = byId.get(r.id);
      if (!entry) {
        entry = { id: r.id, name: r.name, address: r.address, tags: new Set() };
        byId.set(r.id, entry);
      }
      entry.tags.add(r.cuisine_name);
    }
    return [...byId.values()]
      .map((e) => ({ ...e, tags: [...e.tags].sort() }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [rows, browseCity, browseType, browseCuisine]);

  if (user === undefined || rows === null) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-zinc-50 px-6 dark:bg-black">
        {loadError ? (
          <p className="text-sm text-red-600 dark:text-red-400">{loadError}</p>
        ) : (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
        )}
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-zinc-50 px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-3xl flex-col gap-8">
        <div className="flex items-start justify-between gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">
              Your Starred Places
            </h1>
            <p className="text-zinc-600 dark:text-zinc-400">
              Everywhere you&apos;ve starred, mapped and browsable.
            </p>
          </div>
          <Link
            href="/"
            className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Back to search
          </Link>
        </div>

        {rows.length === 0 ? (
          <p className="py-16 text-center text-sm text-zinc-500 dark:text-zinc-400">
            You haven&apos;t starred any restaurants yet. Head back to search and tap the star on
            a place you like.
          </p>
        ) : (
          <>
            <div className="flex gap-1 self-start rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
              <button
                type="button"
                onClick={() => setTab("map")}
                className={tabButtonClass(tab === "map")}
              >
                Map
              </button>
              <button
                type="button"
                onClick={() => setTab("browse")}
                className={tabButtonClass(tab === "browse")}
              >
                Browse
              </button>
            </div>

            {tab === "map" ? (
              <div className="flex flex-col gap-4">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <select
                    value={mapType}
                    onChange={(e) => {
                      setMapType(e.target.value);
                      setMapCuisine("");
                    }}
                    className={selectClass}
                    aria-label="Type"
                  >
                    <option value="">All types</option>
                    {mapTypeOptions.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>

                  <select
                    value={mapCuisine}
                    onChange={(e) => setMapCuisine(e.target.value)}
                    className={selectClass}
                    aria-label="Cuisine"
                  >
                    <option value="">All cuisines</option>
                    {mapCuisineOptions.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>

                  <select
                    value={jumpToKey}
                    onChange={(e) => handleJumpTo(e.target.value)}
                    className={selectClass}
                    aria-label="Jump to"
                  >
                    <option value="">Jump to…</option>
                    {jumpToOptions.map((k) => (
                      <option key={k} value={k}>
                        {k}
                      </option>
                    ))}
                  </select>
                </div>

                <StarredMap
                  entities={mapMarkerEntities}
                  jumpTo={jumpTarget}
                  onBoundsChange={handleBoundsChange}
                />

                <div className="flex flex-col gap-2">
                  <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                    {mapViewportList.length} in view
                  </h2>
                  {mapViewportList.length === 0 ? (
                    <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                      No starred places match here. Pan/zoom the map or adjust the filters.
                    </p>
                  ) : (
                    <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
                      {mapViewportList.map((e) => (
                        <li key={e.id} className="flex flex-col gap-0.5 py-3">
                          <span className="font-medium text-zinc-950 dark:text-zinc-50">
                            {e.name}
                          </span>
                          <span className="text-sm text-zinc-500 dark:text-zinc-400">
                            {e.address}
                          </span>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex flex-col gap-4">
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                  <select
                    value={browseCity}
                    onChange={(e) => {
                      setBrowseCity(e.target.value);
                      setBrowseType("");
                      setBrowseCuisine("");
                    }}
                    className={selectClass}
                    aria-label="City"
                  >
                    <option value="">All cities</option>
                    {browseCityOptions.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>

                  <select
                    value={browseType}
                    onChange={(e) => {
                      setBrowseType(e.target.value);
                      setBrowseCuisine("");
                    }}
                    className={selectClass}
                    aria-label="Type"
                  >
                    <option value="">All types</option>
                    {browseTypeOptions.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>

                  <select
                    value={browseCuisine}
                    onChange={(e) => setBrowseCuisine(e.target.value)}
                    className={selectClass}
                    aria-label="Cuisine"
                  >
                    <option value="">All cuisines</option>
                    {browseCuisineOptions.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="flex flex-col gap-2">
                  <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                    {browseList.length} {browseList.length === 1 ? "place" : "places"}
                  </h2>
                  {browseList.length === 0 ? (
                    <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                      No starred places match those filters.
                    </p>
                  ) : (
                    <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
                      {browseList.map((e) => (
                        <li key={e.id} className="flex flex-col gap-0.5 py-3">
                          <span className="font-medium text-zinc-950 dark:text-zinc-50">
                            {e.name}
                          </span>
                          <span className="text-sm text-zinc-500 dark:text-zinc-400">
                            {e.address}
                          </span>
                          <span className="text-xs text-zinc-500 dark:text-zinc-400">
                            {e.tags.join(" · ")}
                          </span>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </main>
  );
}
