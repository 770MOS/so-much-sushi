"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SearchForm from "@/components/results/SearchForm";
import FilterBar, { SortAndDistance } from "@/components/results/FilterBar";
import ResultRow from "@/components/results/ResultRow";
import JoinNote from "@/components/results/JoinNote";
import type { MapMarkerEntity } from "@/components/EntityMap";
import { useResults } from "@/lib/useResults";
import { useCategoryNames } from "@/lib/useCategories";
import { setResultsState } from "@/lib/resultsStore";
import { parseResultsQuery, resultsHref, type ResultsQuery } from "@/lib/resultsQuery";
import { getLastSearchCoords, getLastSearchLabel, setLastSearchLabel } from "@/lib/lastSearchCoords";
import { geocodeLocationText } from "@/lib/locationLookup";
import { topLevelTypeForCategoryPaths, TYPE_OPTIONS } from "@/lib/entityTypes";
import { useGeolocation } from "@/lib/useGeolocation";
import { reverseGeocode } from "@/lib/reverseGeocode";
import { useIsDesktop } from "@/lib/useIsDesktop";

const EntityMap = dynamic(() => import("@/components/EntityMap"), { ssr: false });

function MapIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 7l6 -3l6 3l6 -3v13l-6 3l-6 -3l-6 3v-13M9 4v13M15 7v13" />
    </svg>
  );
}

function ListIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01" />
    </svg>
  );
}

// The one results page (build step 2): replaces Search and Discover. Everything about the
// search lives in the address (see src/lib/resultsQuery.ts); this page reads it, finds the
// point to search around, runs the search and its counts, and shows List, Split or Map.
export default function ResultsPage() {
  const router = useRouter();
  const params = useSearchParams();
  const query = useMemo(() => parseResultsQuery(params), [params]);
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [joinOpen, setJoinOpen] = useState(false);
  const [hoverId, setHoverId] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);
  const [placeError, setPlaceError] = useState<string | null>(null);
  const names = useCategoryNames();
  const geo = useGeolocation();
  const isDesktop = useIsDesktop();

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => subscription.unsubscribe();
  }, [supabase]);

  const update = useCallback(
    (patch: Partial<ResultsQuery>) => router.replace(resultsHref({ ...query, ...patch }), { scroll: false }),
    [router, query]
  );

  // No point in the address: look up a typed place, else go back to this session's last search,
  // else a member's home area. The point found goes into the address, so the page and its
  // address always agree. Visitors with none of these get the welcome below.
  const needsPoint = query.lat === null || query.lng === null;
  useEffect(() => {
    if (!needsPoint || user === undefined) return;
    let cancelled = false;
    (async () => {
      if (query.where.trim()) {
        setLocating(true);
        const coords = await geocodeLocationText(query.where);
        if (cancelled) return;
        setLocating(false);
        if (coords) update({ lat: coords.lat, lng: coords.lng });
        else setPlaceError("We couldn't find that place. Try a city, town or ZIP code.");
        return;
      }
      const last = getLastSearchCoords();
      if (last) {
        update({ lat: last.lat, lng: last.lng, where: getLastSearchLabel() ?? "" });
        return;
      }
      if (user) {
        const { data } = await supabase.rpc("get_my_home_location");
        const row = data?.[0];
        const home = [row?.home_city, row?.home_state].filter(Boolean).join(", ");
        if (cancelled || !home) return;
        setLocating(true);
        const coords = await geocodeLocationText(home);
        if (cancelled) return;
        setLocating(false);
        if (coords) update({ lat: coords.lat, lng: coords.lng, where: home });
      }
    })();
    return () => {
      cancelled = true;
    };
    // Runs again only when the point or the person changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [needsPoint, query.where, user]);

  useEffect(() => {
    if (query.where.trim() && !needsPoint) setLastSearchLabel(query.where);
  }, [query.where, needsPoint]);

  const args =
    !needsPoint && user !== undefined
      ? { lat: query.lat as number, lng: query.lng as number, r: query.r, kind: query.kind, q: query.q, only: query.only, hidden: query.hidden }
      : null;
  const userId = user?.id ?? null;
  const search = useResults(userId, args);

  useEffect(() => {
    setResultsState({
      origin: !needsPoint ? { lat: query.lat as number, lng: query.lng as number } : null,
      facets: search.facets,
    });
  }, [needsPoint, query.lat, query.lng, search.facets]);

  const rows = useMemo(() => {
    const all = (search.results ?? []).filter((r) => query.hidden || !search.hiddenIds.has(r.id));
    return query.sort === "az" ? [...all].sort((a, b) => a.name.localeCompare(b.name)) : all;
  }, [search.results, search.hiddenIds, query.hidden, query.sort]);

  const markers: MapMarkerEntity[] = useMemo(
    () =>
      rows.map((r) => ({
        id: r.id,
        name: r.name,
        address: r.address,
        lat: r.lat,
        lng: r.lng,
        matchesFilter: true,
        isStarred: search.starredIds.has(r.id),
        recommendedCount: r.recommended_count,
        isWant: r.is_want,
        status: r.status,
        entityType: topLevelTypeForCategoryPaths(r.category_paths),
      })),
    [rows, search.starredIds]
  );

  const kindName = useCallback((path: string) => names.get(path) ?? path.split(".").pop()!.replace(/_/g, " "), [names]);

  async function locateMe() {
    const coords = await geo.requestLocation();
    if (!coords) return;
    const next = { ...query, lat: coords.lat, lng: coords.lng, where: "Current location" };
    router.replace(resultsHref(next), { scroll: false });
    reverseGeocode(coords).then((label) => {
      if (label) router.replace(resultsHref({ ...next, where: label }), { scroll: false });
    });
  }

  const total = rows.length > 0 ? (search.results?.[0]?.total_count ?? rows.length) : 0;
  const capped = (search.results?.length ?? 0) >= 1000 && total > (search.results?.length ?? 0);
  const fitKey = args ? JSON.stringify({ ...args, hidden: undefined }) : undefined;
  const showMapOnPhone = query.view === "map";
  const placeWord = (n: number) => (n === 1 ? "place" : "places");

  // ------------------------------------------------------------------ no point yet
  if (needsPoint) {
    return (
      <main className="flex flex-1 flex-col">
        <div className="border-b border-line px-4 py-3 md:hidden">
          <SearchForm layout="stacked" />
        </div>
        <section className="mx-auto flex w-full max-w-xl flex-1 flex-col gap-6 px-6 py-12">
          <h1 className="text-3xl font-medium leading-tight tracking-tight text-zinc-950">
            Every place to eat and drink. Nothing paid to the top.
          </h1>
          <p className="text-base text-muted">
            Restaurants, bars, coffee shops and markets, in the order you choose. No ads, no sponsored spots, no scores.
          </p>
          {locating || user === undefined ? (
            <p className="text-sm text-muted">Finding where to start…</p>
          ) : (
            <div className="flex flex-col gap-3">
              <button
                type="button"
                onClick={locateMe}
                disabled={geo.locating}
                className="h-12 rounded-xl bg-primary px-5 text-base font-medium text-white hover:bg-primary-hover disabled:opacity-50"
              >
                {geo.locating ? "Finding your location…" : "Use my location"}
              </button>
              <p className="text-sm text-muted">Or type a city, town or ZIP code in Where.</p>
              {(geo.geoError || placeError) && <p className="text-sm text-red-700">{geo.geoError || placeError}</p>}
            </div>
          )}
          <div className="flex flex-col gap-3">
            <h2 className="text-sm font-medium text-muted">Browse by type</h2>
            <div className="grid grid-cols-2 gap-2">
              {TYPE_OPTIONS.filter((t) => t.key !== "all").map((t) => (
                <button
                  key={t.key}
                  type="button"
                  onClick={() => update({ kind: t.key })}
                  aria-pressed={query.kind === t.key}
                  className={`flex h-12 items-center rounded-xl border px-4 text-left text-[15px] font-medium ${
                    query.kind === t.key ? "border-primary bg-primary text-white" : "border-line text-zinc-950 hover:border-zinc-400"
                  }`}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </div>
        </section>
      </main>
    );
  }

  // ------------------------------------------------------------------ results
  const list = (card: boolean) => (
    <>
      {search.loading && !search.results ? (
        <p className="px-6 py-10 text-center text-sm text-muted">Searching…</p>
      ) : rows.length === 0 ? (
        <div className="px-6 py-10 text-center text-sm text-muted">
          {search.error ?? "No places match. Try another kind, a wider distance, or turning a filter off."}
        </div>
      ) : (
        <ul className={card ? "grid gap-3 px-4 py-3 md:px-6 lg:grid-cols-2" : ""} aria-busy={search.loading}>
          {rows.map((r) => (
            <ResultRow
              key={r.id}
              r={r}
              card={card}
              starred={search.starredIds.has(r.id)}
              hidden={search.hiddenIds.has(r.id)}
              userId={userId}
              onToggleStar={() => search.toggleStar(r.id)}
              onToggleHide={() => search.toggleHide(r.id)}
              onLocked={() => setJoinOpen(true)}
              onHover={setHoverId}
              highlighted={hoverId === r.id}
            />
          ))}
        </ul>
      )}
      <div className="flex flex-col items-center gap-2 px-6 py-6 text-center text-sm text-muted">
        {userId && (search.facets?.hidden ?? 0) > 0 && !query.hidden && (
          <p>
            {search.facets!.hidden} {placeWord(search.facets!.hidden)} you hid {search.facets!.hidden === 1 ? "isn’t" : "aren’t"} shown.{" "}
            <button type="button" onClick={() => update({ hidden: true })} className="font-medium text-zinc-950 underline">
              Show {search.facets!.hidden === 1 ? "it" : "them"}
            </button>
          </p>
        )}
        {query.hidden && (
          <button type="button" onClick={() => update({ hidden: false })} className="font-medium text-zinc-950 underline">
            Leave out places you hid
          </button>
        )}
        <p>
          Can&apos;t find a place?{" "}
          <Link href={query.q ? `/request?name=${encodeURIComponent(query.q)}` : "/request"} className="font-medium text-zinc-950 underline">
            Request it
          </Link>
        </p>
      </div>
    </>
  );

  const header = (
    <div className="flex flex-col gap-0.5 px-5 pb-2 pt-3 md:px-6">
      <p className="text-[15px] text-zinc-950" aria-live="polite">
        {search.loading && !search.results ? (
          "Searching…"
        ) : (
          <>
            <span className="font-medium">
              {capped
                ? `Nearest ${(search.results?.length ?? 0).toLocaleString("en-US")} of ${total.toLocaleString("en-US")} places`
                : `${rows.length.toLocaleString("en-US")} ${placeWord(rows.length)}`}
            </span>
            <span className="text-muted">
              {query.q ? ` named “${query.q}”` : ""}
              {query.where ? ` near ${query.where}` : " nearby"}
            </span>
          </>
        )}
      </p>
      {capped && <p className="text-[13px] text-muted">Only the nearest are shown. A shorter distance, a kind or a name narrows the list.</p>}
      <SortAndDistance query={query} onChange={update} />
    </div>
  );

  const map = (className: string) => (
    <EntityMap
      entities={markers}
      onToggleStar={(id) => (userId ? search.toggleStar(id) : setJoinOpen(true))}
      fitKey={fitKey}
      highlightId={hoverId}
      className={className}
    />
  );

  return (
    <main className="flex flex-1 flex-col">
      <div className="border-b border-line px-4 py-3 md:hidden">
        <SearchForm layout="stacked" />
      </div>
      <FilterBar
        query={query}
        facets={search.facets}
        signedIn={Boolean(userId)}
        kindName={kindName}
        onChange={update}
        onLocked={() => setJoinOpen(true)}
      />

      {/* Phone: one view at a time, with a button to switch. */}
      {isDesktop === false && (
        <div>
          {showMapOnPhone ? (
            map("h-[calc(100dvh-230px)] w-full")
          ) : (
            <>
              {header}
              {list(false)}
            </>
          )}
          <button
            type="button"
            onClick={() => update({ view: showMapOnPhone ? "list" : "map" })}
            className="fixed bottom-[92px] left-1/2 z-10 inline-flex h-12 -translate-x-1/2 items-center gap-2 rounded-full bg-primary px-5 text-[15px] font-medium text-white shadow-[0_4px_14px_rgba(0,0,0,0.25)]"
          >
            {showMapOnPhone ? <ListIcon /> : <MapIcon />}
            {showMapOnPhone ? "List" : "Map"}
          </button>
        </div>
      )}

      {/* Computer: List, Split or Map. */}
      {isDesktop && (
        <div>
          {query.view === "list" && (
            <div className="mx-auto w-full max-w-6xl">
              {header}
              {list(true)}
            </div>
          )}
          {query.view === "split" && (
            <div className="flex items-start">
              <section aria-label="Results" className="w-[440px] shrink-0 border-r border-line">
                {header}
                {list(false)}
              </section>
              <section aria-label="Map" className="sticky top-0 h-[100dvh] min-w-0 flex-1">
                {map("h-full w-full")}
              </section>
            </div>
          )}
          {query.view === "map" && (
            <section aria-label="Map" className="relative">
              {map("h-[calc(100dvh-140px)] min-h-[480px] w-full")}
              <p className="absolute left-1/2 top-3 -translate-x-1/2 rounded-full bg-white/95 px-4 py-2 text-sm text-zinc-950 shadow-[0_2px_10px_rgba(0,0,0,0.12)]">
                {rows.length.toLocaleString("en-US")} {placeWord(rows.length)}
                {query.where ? ` near ${query.where}` : ""}
              </p>
            </section>
          )}
        </div>
      )}

      <JoinNote open={joinOpen} onClose={() => setJoinOpen(false)} />
    </main>
  );
}
