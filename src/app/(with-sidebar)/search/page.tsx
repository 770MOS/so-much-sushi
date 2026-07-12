"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SearchResultsView from "@/components/SearchResultsView";
import { useEntitySearch } from "@/lib/useEntitySearch";
import { useGeolocation } from "@/lib/useGeolocation";
import { getLastSearchCoords } from "@/lib/lastSearchCoords";

// A name-only lookup should never miss a known place because of distance -
// this is generously larger than the current Arlington-only dataset's
// extent, with headroom if the data footprint grows.
const MAX_RADIUS_MILES = 500;

export default function SearchPage() {
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null>(null);
  const [name, setName] = useState("");

  const search = useEntitySearch(user);
  const geo = useGeolocation("Try searching manually from the home page instead.");

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  async function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!name.trim() || search.loading) return;

    search.setLoading(true);
    search.setError(null);
    search.setResults(null);

    try {
      let coords = getLastSearchCoords();
      if (!coords) {
        coords = await geo.requestLocation();
      }
      if (!coords) {
        search.setError("We need a location to search from. Try the home page instead.");
        return;
      }

      await search.runSearch({
        lat: coords.lat,
        lng: coords.lng,
        radiusMiles: MAX_RADIUS_MILES,
        nameQuery: name,
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
              htmlFor="name"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Name
            </label>
            <input
              id="name"
              type="text"
              placeholder="Restaurant, bar, or cafe name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-none border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
            />
          </div>

          <button
            type="submit"
            disabled={search.loading || !name.trim()}
            className="w-full rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
          >
            {search.loading ? "Searching…" : "Search"}
          </button>
        </form>

        {geo.geoError && <p className="text-sm text-red-600 dark:text-red-400">{geo.geoError}</p>}
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
          emptyMessage="No matches yet. Try a different name."
        />
      </div>
    </main>
  );
}
