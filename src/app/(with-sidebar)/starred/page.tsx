"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SearchResultsView from "@/components/SearchResultsView";
import { useEntitySearch } from "@/lib/useEntitySearch";
import { useGeolocation } from "@/lib/useGeolocation";
import { getLastSearchCoords } from "@/lib/lastSearchCoords";

const DEFAULT_RADIUS = 10;

export default function StarredQuickView() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const search = useEntitySearch(user ?? null);
  const geo = useGeolocation("Try searching manually from the home page instead.");

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
    (async () => {
      await Promise.resolve();
      if (cancelled) return;

      let coords = getLastSearchCoords();
      if (!coords) {
        coords = await geo.requestLocation();
      }
      if (!coords || cancelled) return;

      search.setLoading(true);
      search.setError(null);
      try {
        await search.runSearch({
          lat: coords.lat,
          lng: coords.lng,
          radiusMiles: DEFAULT_RADIUS,
          starredOnly: true,
        });
      } finally {
        if (!cancelled) search.setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- search/geo are re-created every render; only re-run when the signed-in user changes
  }, [user]);

  if (user === undefined) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-white px-6 dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-8">
        <div className="flex items-start justify-between gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Starred</h1>
            <p className="text-zinc-600 dark:text-zinc-400">
              Your starred places near your current search location.
            </p>
          </div>
          <Link
            href="/profile"
            className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Browse all starred places
          </Link>
        </div>

        {geo.geoError && <p className="text-sm text-red-600 dark:text-red-400">{geo.geoError}</p>}
        {search.error && <p className="text-sm text-red-600 dark:text-red-400">{search.error}</p>}

        {geo.locating && (
          <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            Finding your location…
          </p>
        )}

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
          emptyMessage="No starred places found nearby. Browse all your starred places instead."
        />
      </div>
    </main>
  );
}
