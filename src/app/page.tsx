"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import dynamic from "next/dynamic";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import AddToListMenu from "@/components/AddToListMenu";
import StatusBadge from "@/components/StatusBadge";
import type { MapMarkerEntity } from "@/components/EntityMap";

const EntityMap = dynamic(() => import("@/components/EntityMap"), { ssr: false });

const CURRENT_LOCATION_LABEL = "Current location";

type Category = {
  id: string;
  name: string;
  path: string;
};

type SearchResult = {
  id: string;
  name: string;
  address: string;
  miles: number;
  lat: number;
  lng: number;
  is_starred: boolean;
  is_hidden: boolean;
  recommended_by: (string | null)[] | null;
  recommended_count: number;
  status: string;
  categories: string[] | null;
};

type SortMode = "nearest" | "az";
type ViewMode = "list" | "map";

function categoryIndent(path: string) {
  const depth = (path.match(/\./g) ?? []).length;
  return "    ".repeat(depth);
}

function sortButtonClass(active: boolean) {
  return `rounded-md px-3 py-1 text-sm font-medium transition-colors ${
    active
      ? "bg-primary text-white"
      : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
  }`;
}

function HeartIcon() {
  return (
    <svg viewBox="0 0 24 24" width={14} height={14} fill="currentColor" className="text-rose-400">
      <path d="M12 21s-6.716-4.35-9.428-8.06C.85 10.42 1.2 7.03 3.79 5.3 6.02 3.8 8.94 4.4 10.5 6.3 12.06 4.4 14.98 3.8 17.21 5.3c2.59 1.73 2.94 5.12 1.22 7.64C18.72 16.65 12 21 12 21z" />
    </svg>
  );
}

function recommendationLabel(
  recommendedBy: (string | null)[] | null,
  recommendedCount: number
): string | null {
  if (!recommendedCount) return null;

  const names = (recommendedBy ?? []).map((n) => (n && n.trim() ? n : "a friend"));
  const first = names[0] ?? "a friend";

  if (recommendedCount === 1) return `Starred by ${first}`;
  if (recommendedCount === 2) return `Starred by ${first} and ${names[1] ?? "a friend"}`;
  return `Starred by ${first} and ${recommendedCount - 1} others`;
}

function StarIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={20}
      height={20}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={1.5}
      className={filled ? "text-amber-400" : "text-zinc-400"}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.8L12 16.9l-5.2 2.62.99-5.8-4.21-4.1 5.82-.85L12 3.5z"
      />
    </svg>
  );
}

function CrosshairIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <circle cx="12" cy="12" r="7" strokeLinecap="round" strokeLinejoin="round" />
      <path strokeLinecap="round" d="M12 2v3M12 19v3M2 12h3M19 12h3" />
      <circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none" />
    </svg>
  );
}

function EyeOffIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={20}
      height={20}
      fill="none"
      stroke="currentColor"
      strokeWidth={filled ? 2 : 1.5}
      className={filled ? "text-zinc-800 dark:text-zinc-100" : "text-zinc-400"}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M3 3l18 18M10.58 10.58a2 2 0 102.83 2.83M9.88 4.24A9.1 9.1 0 0112 4c5 0 9 4.5 10.5 8-.6 1.36-1.5 2.7-2.6 3.85M6.4 6.4C4.13 7.86 2.44 9.94 1.5 12c1.02 2.28 2.7 4.24 4.76 5.6A9.15 9.15 0 0012 20c1.13 0 2.21-.18 3.22-.51"
      />
    </svg>
  );
}

export default function Home() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [location, setLocation] = useState("");
  const [radius, setRadius] = useState(10);
  const [categoryPath, setCategoryPath] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [sortMode, setSortMode] = useState<SortMode>("nearest");
  const [viewMode, setViewMode] = useState<ViewMode>("list");
  const [starredIds, setStarredIds] = useState<Set<string>>(new Set());
  const [hiddenIds, setHiddenIds] = useState<Set<string>>(new Set());
  const [recommendedOnly, setRecommendedOnly] = useState(false);
  const [showHidden, setShowHidden] = useState(false);
  const [lastCoords, setLastCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [locating, setLocating] = useState(false);
  const [geoError, setGeoError] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    async function loadCategories() {
      const { data } = await supabase
        .from("categories")
        .select("id, name, path")
        .order("path");
      if (data) setCategories(data);
    }
    loadCategories();
  }, [supabase]);

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
    }));
  }, [sortedResults, starredIds]);

  async function runSearch(
    lat: number,
    lng: number,
    recommendedOnlyValue: boolean,
    showHiddenValue: boolean
  ) {
    const { data, error: rpcError } = await supabase.rpc("search_entities", {
      ref_lat: lat,
      ref_lng: lng,
      radius_miles: radius,
      category_path: categoryPath || null,
      recommended_only: recommendedOnlyValue,
      show_hidden: showHiddenValue,
    });

    if (rpcError) {
      setError("Something went wrong while searching. Please try again.");
      return;
    }

    const searchResults: SearchResult[] = data ?? [];
    setResults(searchResults);
    setStarredIds(new Set(searchResults.filter((r) => r.is_starred).map((r) => r.id)));
    setHiddenIds(new Set(searchResults.filter((r) => r.is_hidden).map((r) => r.id)));
  }

  async function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!location.trim() || loading) return;

    setLoading(true);
    setError(null);
    setResults(null);

    try {
      if (location === CURRENT_LOCATION_LABEL && lastCoords) {
        await runSearch(lastCoords.lat, lastCoords.lng, recommendedOnly, showHidden);
        return;
      }

      const geocodeRes = await fetch(
        `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=${encodeURIComponent(location)}`
      );
      const geocodeData = await geocodeRes.json();

      if (!geocodeRes.ok || !geocodeData.length) {
        setError("We couldn't find that location. Try a ZIP code or a fuller address.");
        return;
      }

      const { lat, lon } = geocodeData[0];
      const coords = { lat: parseFloat(lat), lng: parseFloat(lon) };
      setLastCoords(coords);
      await runSearch(coords.lat, coords.lng, recommendedOnly, showHidden);
    } catch {
      setError("Something went wrong. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  function handleUseMyLocation() {
    setGeoError(null);

    if (!("geolocation" in navigator)) {
      setGeoError("Geolocation isn't supported by your browser. Please enter a location manually.");
      return;
    }

    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        setLocating(false);
        const coords = { lat: position.coords.latitude, lng: position.coords.longitude };
        setLocation(CURRENT_LOCATION_LABEL);
        setLastCoords(coords);

        setLoading(true);
        setError(null);
        setResults(null);
        try {
          await runSearch(coords.lat, coords.lng, recommendedOnly, showHidden);
        } catch {
          setError("Something went wrong. Please check your connection and try again.");
        } finally {
          setLoading(false);
        }
      },
      (err) => {
        setLocating(false);
        if (err.code === err.PERMISSION_DENIED) {
          setGeoError("Location access was denied. Please enter a location manually.");
        } else {
          setGeoError("We couldn't determine your location. Please enter a location manually.");
        }
      }
    );
  }

  async function toggleRecommendedOnly() {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    const next = !recommendedOnly;
    setRecommendedOnly(next);

    if (!lastCoords || loading) return;

    setLoading(true);
    setError(null);
    try {
      await runSearch(lastCoords.lat, lastCoords.lng, next, showHidden);
    } catch {
      setError("Something went wrong. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  async function toggleShowHidden() {
    const next = !showHidden;
    setShowHidden(next);

    if (!lastCoords || loading) return;

    setLoading(true);
    setError(null);
    try {
      await runSearch(lastCoords.lat, lastCoords.lng, recommendedOnly, next);
    } catch {
      setError("Something went wrong. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
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

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex flex-col gap-2">
          <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">
            So Much Sushi
          </h1>
          <p className="text-zinc-600 dark:text-zinc-400">
            Find restaurants near you. No ads, no accounts, just search.
          </p>
        </div>

        <form onSubmit={handleSearch} className="flex flex-col gap-8">
          <div className="flex flex-col gap-2">
            <label
              htmlFor="location"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Location
            </label>
            <div className="flex gap-2">
              <input
                id="location"
                type="text"
                placeholder="ZIP code or address"
                value={location}
                onChange={(e) => {
                  setGeoError(null);
                  setLocation(e.target.value);
                }}
                className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
              />
              <button
                type="button"
                onClick={handleUseMyLocation}
                disabled={locating}
                className="flex shrink-0 items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-2.5 text-sm font-medium text-zinc-600 transition-colors hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
              >
                <CrosshairIcon />
                <span className="whitespace-nowrap">{locating ? "Locating…" : "Use my location"}</span>
              </button>
            </div>
            {geoError && (
              <p className="text-xs text-red-600 dark:text-red-400">{geoError}</p>
            )}
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
              <label
                htmlFor="radius"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Radius
              </label>
              <span className="text-sm text-zinc-500 dark:text-zinc-400">{radius} mi</span>
            </div>
            <input
              id="radius"
              type="range"
              min={1}
              max={25}
              value={radius}
              onChange={(e) => setRadius(Number(e.target.value))}
              className="w-full accent-zinc-900 dark:accent-zinc-100"
            />
          </div>

          <div className="flex flex-col gap-2">
            <label
              htmlFor="category"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Category
            </label>
            <select
              id="category"
              value={categoryPath}
              onChange={(e) => setCategoryPath(e.target.value)}
              className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
            >
              <option value="">All categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.path}>
                  {categoryIndent(c.path)}
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <button
            type="submit"
            disabled={loading || !location.trim()}
            className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
          >
            {loading ? "Searching…" : "Search"}
          </button>
        </form>

        {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

        {loading && (
          <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            Searching…
          </p>
        )}

        {!loading && results !== null && (
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                {results.length} {results.length === 1 ? "result" : "results"}
              </h2>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={toggleRecommendedOnly}
                  aria-pressed={recommendedOnly}
                  className={`rounded-lg border px-3 py-1 text-sm font-medium transition-colors ${
                    recommendedOnly
                      ? "border-primary bg-primary text-white"
                      : "border-zinc-300 text-zinc-600 hover:text-zinc-900 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
                  }`}
                >
                  Recommended only
                </button>
                <button
                  type="button"
                  onClick={toggleShowHidden}
                  aria-pressed={showHidden}
                  className={`rounded-lg border px-3 py-1 text-sm font-medium transition-colors ${
                    showHidden
                      ? "border-primary bg-primary text-white"
                      : "border-zinc-300 text-zinc-600 hover:text-zinc-900 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
                  }`}
                >
                  Show hidden
                </button>
                <div className="flex gap-1 rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
                  <button
                    type="button"
                    onClick={() => setViewMode("list")}
                    className={sortButtonClass(viewMode === "list")}
                  >
                    List
                  </button>
                  <button
                    type="button"
                    onClick={() => setViewMode("map")}
                    className={sortButtonClass(viewMode === "map")}
                  >
                    Map
                  </button>
                </div>
                {results.length > 0 && viewMode === "list" && (
                  <div className="flex gap-1 rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
                    <button
                      type="button"
                      onClick={() => setSortMode("nearest")}
                      className={sortButtonClass(sortMode === "nearest")}
                    >
                      Nearest
                    </button>
                    <button
                      type="button"
                      onClick={() => setSortMode("az")}
                      className={sortButtonClass(sortMode === "az")}
                    >
                      A&ndash;Z
                    </button>
                  </div>
                )}
              </div>
            </div>

            {recommendedOnly && (
              <p className="text-xs text-zinc-500 dark:text-zinc-400">
                Showing places starred by your connections
              </p>
            )}

            {results.length === 0 ? (
              <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                No restaurants found nearby. Try a larger radius or a different category.
              </p>
            ) : viewMode === "map" ? (
              <EntityMap entities={mapMarkerEntities} />
            ) : (
              <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
                {sortedResults.map((r) => {
                  const recLabel = recommendationLabel(r.recommended_by, r.recommended_count);
                  return (
                  <li key={r.id} className="flex items-center justify-between gap-4 py-4">
                    <div className="flex flex-col gap-0.5">
                      <span className="font-medium text-zinc-950 dark:text-zinc-50">
                        {r.name}
                      </span>
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">
                        {r.address}
                      </span>
                      {r.categories && r.categories.length > 0 && (
                        <span className="text-xs text-zinc-500 dark:text-zinc-400">
                          {r.categories.join(", ")}
                        </span>
                      )}
                      <StatusBadge status={r.status} />
                      {recLabel && (
                        <span className="flex items-center gap-1 text-xs text-zinc-500 dark:text-zinc-400">
                          <HeartIcon />
                          {recLabel}
                        </span>
                      )}
                    </div>
                    <div className="flex shrink-0 items-center gap-3">
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">
                        {r.miles.toFixed(1)} mi
                      </span>
                      {user && <AddToListMenu userId={user.id} entityId={r.id} />}
                      <button
                        type="button"
                        onClick={() => toggleStar(r.id)}
                        aria-label={starredIds.has(r.id) ? "Unstar" : "Star"}
                        aria-pressed={starredIds.has(r.id)}
                        className="rounded p-1 transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-800"
                      >
                        <StarIcon filled={starredIds.has(r.id)} />
                      </button>
                      <button
                        type="button"
                        onClick={() => toggleHide(r.id)}
                        aria-label={hiddenIds.has(r.id) ? "Unhide" : "Hide"}
                        aria-pressed={hiddenIds.has(r.id)}
                        className="rounded p-1 transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-800"
                      >
                        <EyeOffIcon filled={hiddenIds.has(r.id)} />
                      </button>
                    </div>
                  </li>
                  );
                })}
              </ul>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
