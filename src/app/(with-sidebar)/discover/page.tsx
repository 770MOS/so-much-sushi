"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import LocationInput from "@/components/LocationInput";
import RadiusSlider from "@/components/RadiusSlider";
import TypeSelect from "@/components/TypeSelect";
import SearchResultsView from "@/components/SearchResultsView";
import { useEntitySearch } from "@/lib/useEntitySearch";
import { useGeolocation } from "@/lib/useGeolocation";
import { reverseGeocode } from "@/lib/reverseGeocode";
import { addSearchHistory } from "@/lib/searchHistory";
import { CURRENT_LOCATION_LABEL } from "@/lib/lastSearchCoords";
import { categoryPathForType, type EntityType } from "@/lib/entityTypes";

const DEFAULT_RADIUS = 10;

type Category = {
  id: string;
  name: string;
  path: string;
};

function categoryIndent(path: string) {
  const depth = (path.match(/\./g) ?? []).length;
  return "    ".repeat(depth);
}

export default function DiscoverPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [location, setLocation] = useState("");
  const [radius, setRadius] = useState(DEFAULT_RADIUS);
  const [entityType, setEntityType] = useState<EntityType>("all");
  const [categoryPath, setCategoryPath] = useState("");
  const [recommendedOnly, setRecommendedOnly] = useState(false);
  const [showHidden, setShowHidden] = useState(false);
  const [lastCoords, setLastCoords] = useState<{ lat: number; lng: number } | null>(null);

  const search = useEntitySearch(user);
  const geo = useGeolocation();

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

  function handleTypeSelect(type: EntityType) {
    setEntityType(type);
    setCategoryPath(categoryPathForType(type));
  }

  async function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!location.trim() || search.loading) return;

    search.setLoading(true);
    search.setError(null);
    search.setResults(null);

    try {
      if (location === CURRENT_LOCATION_LABEL && lastCoords) {
        await search.runSearch({
          lat: lastCoords.lat,
          lng: lastCoords.lng,
          radiusMiles: radius,
          categoryPath,
          recommendedOnly,
          showHidden,
        });
        return;
      }

      const geocodeRes = await fetch(
        `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=us&q=${encodeURIComponent(location)}`
      );
      const geocodeData = await geocodeRes.json();

      if (!geocodeRes.ok || !geocodeData.length) {
        search.setError("We couldn't find that location. Try a ZIP code or a fuller address.");
        return;
      }

      const { lat, lon } = geocodeData[0];
      const coords = { lat: parseFloat(lat), lng: parseFloat(lon) };
      setLastCoords(coords);
      await search.runSearch({
        lat: coords.lat,
        lng: coords.lng,
        radiusMiles: radius,
        categoryPath,
        recommendedOnly,
        showHidden,
      });
      addSearchHistory(location);
    } catch {
      search.setError("Something went wrong. Please check your connection and try again.");
    } finally {
      search.setLoading(false);
    }
  }

  async function handleUseMyLocation() {
    const coords = await geo.requestLocation();
    if (!coords) return;

    setLocation(CURRENT_LOCATION_LABEL);
    setLastCoords(coords);

    // Best-effort label, resolved independently of the search below - a slow
    // or failed reverse-geocode should never hold up or break results, since
    // the coordinates already work for search on their own. Only replace the
    // field if the user hasn't since typed something else into it.
    reverseGeocode(coords).then((label) => {
      if (label) {
        setLocation((prev) => (prev === CURRENT_LOCATION_LABEL ? label : prev));
      }
    });

    search.setLoading(true);
    search.setError(null);
    search.setResults(null);
    try {
      await search.runSearch({
        lat: coords.lat,
        lng: coords.lng,
        radiusMiles: radius,
        categoryPath,
        recommendedOnly,
        showHidden,
      });
    } catch {
      search.setError("Something went wrong. Please check your connection and try again.");
    } finally {
      search.setLoading(false);
    }
  }

  async function toggleRecommendedOnly() {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    const next = !recommendedOnly;
    setRecommendedOnly(next);

    if (!lastCoords || search.loading) return;

    search.setLoading(true);
    search.setError(null);
    try {
      await search.runSearch({
        lat: lastCoords.lat,
        lng: lastCoords.lng,
        radiusMiles: radius,
        categoryPath,
        recommendedOnly: next,
        showHidden,
      });
    } catch {
      search.setError("Something went wrong. Please check your connection and try again.");
    } finally {
      search.setLoading(false);
    }
  }

  async function toggleShowHidden() {
    const next = !showHidden;
    setShowHidden(next);

    if (!lastCoords || search.loading) return;

    search.setLoading(true);
    search.setError(null);
    try {
      await search.runSearch({
        lat: lastCoords.lat,
        lng: lastCoords.lng,
        radiusMiles: radius,
        categoryPath,
        recommendedOnly,
        showHidden: next,
      });
    } catch {
      search.setError("Something went wrong. Please check your connection and try again.");
    } finally {
      search.setLoading(false);
    }
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 pt-10 pb-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <form onSubmit={handleSearch} className="flex flex-col gap-8">
          <div className="flex flex-col gap-2">
            <label
              htmlFor="location"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Location
            </label>
            <LocationInput
              id="location"
              value={location}
              onChange={(v) => {
                geo.setGeoError(null);
                setLocation(v);
              }}
              onUseMyLocation={handleUseMyLocation}
              locating={geo.locating}
            />
            {geo.geoError && <p className="text-xs text-red-600 dark:text-red-400">{geo.geoError}</p>}
          </div>

          <div className="flex flex-col gap-2">
            <label
              htmlFor="radius"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Radius
            </label>
            <RadiusSlider id="radius" value={radius} onChange={setRadius} min={1} max={25} />
          </div>

          <TypeSelect value={entityType} onChange={handleTypeSelect} />

          {(entityType === "all" || entityType === "restaurants") && (
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
                <option value={entityType === "restaurants" ? "restaurants" : ""}>
                  {entityType === "restaurants" ? "All restaurants" : "All categories"}
                </option>
                {categories
                  .filter((c) =>
                    entityType === "restaurants" ? c.path.startsWith("restaurants.") : true
                  )
                  .map((c) => (
                    <option key={c.id} value={c.path}>
                      {categoryIndent(c.path)}
                      {c.name}
                    </option>
                  ))}
              </select>
            </div>
          )}

          <button
            type="submit"
            disabled={search.loading || !location.trim()}
            className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
          >
            {search.loading ? "Searching…" : "Search"}
          </button>
        </form>

        {search.error && <p className="text-sm text-red-600 dark:text-red-400">{search.error}</p>}

        <SearchResultsView
          loading={search.loading}
          results={search.results}
          sortedResults={search.sortedResults}
          mapMarkerEntities={search.mapMarkerEntities}
          viewMode={search.viewMode}
          setViewMode={search.setViewMode}
          sortMode={search.sortMode}
          setSortMode={search.setSortMode}
          starredIds={search.starredIds}
          toggleStar={search.toggleStar}
          hiddenIds={search.hiddenIds}
          toggleHide={search.toggleHide}
          user={user}
          note={
            recommendedOnly ? (
              <p className="text-xs text-zinc-500 dark:text-zinc-400">
                Showing places starred by your connections
              </p>
            ) : undefined
          }
          extraControls={
            <>
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
            </>
          }
        />
      </div>
    </main>
  );
}
