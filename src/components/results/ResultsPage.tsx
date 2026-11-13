"use client";

import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SearchForm from "@/components/results/SearchForm";
import FilterBar, { SortMenu } from "@/components/results/FilterBar";
import ResultRow from "@/components/results/ResultRow";
import JoinNote from "@/components/results/JoinNote";
import type { MapMarkerEntity } from "@/components/EntityMap";
import { useResults } from "@/lib/useResults";
import { useCategoryNames } from "@/lib/useCategories";
import { setResultsState } from "@/lib/resultsStore";
import {
  boxCenter,
  boxContains,
  boxParam,
  boxTooLarge,
  MAP_AREA_LABEL,
  parseResultsQuery,
  resultsHref,
  sameBox,
  type Box,
  type ResultsQuery,
} from "@/lib/resultsQuery";
import { CURRENT_LOCATION_LABEL, getLastSearchArea, setLastSearchArea } from "@/lib/lastSearchCoords";
import { geocodeLocationText } from "@/lib/locationLookup";
import { startArea } from "@/lib/searchArea";
import { fetchIpArea } from "@/lib/ipArea";
import { pushResults, replaceResults } from "@/lib/resultsNav";
import { topLevelTypeForCategoryPaths, TYPE_OPTIONS } from "@/lib/entityTypes";
import { useGeolocation } from "@/lib/useGeolocation";
import { reverseGeocode } from "@/lib/reverseGeocode";
import { useIsDesktop } from "@/lib/useIsDesktop";

const ResultsMap = dynamic(() => import("@/components/results/ResultsMap"), { ssr: false });

function MapIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 7l6 -3l6 3l6 -3v13l-6 3l-6 -3l-6 3v-13M9 4v13M15 7v13" />
    </svg>
  );
}

function RefreshIcon() {
  return (
    <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M20 11a8.1 8.1 0 0 0 -15.5 -2m-.5 -4v4h4M4 13a8.1 8.1 0 0 0 15.5 2m.5 4v-4h-4" />
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

// The one results page (build steps 2 and 3): replaces Search and Discover. Everything about
// the search lives in the address (see src/lib/resultsQuery.ts); this page reads it, finds the
// area to search when the address has none, runs the search and its counts, and shows List,
// Split or Map. The map area is the search area: moving the map offers "Search this area".
export default function ResultsPage() {
  const params = useSearchParams();
  const query = useMemo(() => parseResultsQuery(params), [params]);
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [joinOpen, setJoinOpen] = useState(false);
  const [hoverId, setHoverId] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);
  const [placeError, setPlaceError] = useState<string | null>(null);
  // The area guessed from the visitor's internet connection, while the search is still on it.
  const [approxArea, setApproxArea] = useState<string | null>(null);
  // Where the person moved the map to, for the search area it was moved from.
  const [moved, setMoved] = useState<{ areaKey: string; view: Box } | null>(null);
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

  const update = useCallback((patch: Partial<ResultsQuery>) => replaceResults(resultsHref({ ...query, ...patch })), [query]);

  // The search area, kept as the same object while its edges stay the same, so changing a
  // filter doesn't move the map.
  const areaKey = query.b ? boxParam(query.b) : null;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const area = useMemo(() => query.b, [areaKey]);
  // The point distances are measured from: the one in the address, else the area's middle.
  const point = area ? (query.lat !== null && query.lng !== null ? { lat: query.lat, lng: query.lng } : boxCenter(area)) : null;

  // No area in the address: open on one. A point without an area (an older link): about the
  // nearest 50 places around it. Else a typed place (a town: the whole town). Else this
  // session's last search, a member's home area, or the visitor's area guessed from their
  // internet connection. The area found goes into the address, so the page and its address
  // always agree. With none of these, the welcome below.
  const needsArea = area === null;
  useEffect(() => {
    if (!needsArea || user === undefined) return;
    let cancelled = false;
    async function open(at: { lat: number; lng: number }, where: string, opts: { radiusMiles?: number; minPlaces?: number } = {}) {
      const b = await startArea(supabase, at, opts);
      if (!cancelled) update({ lat: at.lat, lng: at.lng, b, where });
      return b;
    }
    (async () => {
      setLocating(true);
      try {
        if (query.lat !== null && query.lng !== null) {
          await open({ lat: query.lat, lng: query.lng }, query.where);
          return;
        }
        if (query.where.trim() && query.where !== MAP_AREA_LABEL && query.where !== CURRENT_LOCATION_LABEL) {
          const found = await geocodeLocationText(query.where);
          if (cancelled) return;
          if (found) await open(found, query.where, { radiusMiles: found.radiusMiles, minPlaces: found.minPlaces });
          else setPlaceError("We couldn't find that place. Try a city, town or ZIP code.");
          return;
        }
        const last = getLastSearchArea();
        if (last) {
          update({ lat: last.lat, lng: last.lng, b: last.b, where: last.where });
          return;
        }
        if (user) {
          const { data } = await supabase.rpc("get_my_home_location");
          const row = data?.[0];
          const home = [row?.home_city, row?.home_state].filter(Boolean).join(", ");
          const found = home ? await geocodeLocationText(home) : null;
          if (cancelled) return;
          if (found) {
            await open(found, home, { radiusMiles: found.radiusMiles, minPlaces: found.minPlaces });
            return;
          }
        }
        const ip = await fetchIpArea();
        if (cancelled || !ip) return;
        const b = await open(ip, ip.label);
        if (!cancelled) setApproxArea(boxParam(b));
      } finally {
        if (!cancelled) setLocating(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // Runs again only when the area or the person changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [needsArea, user]);

  // Coming back to the results page later in this session returns to this search's area.
  useEffect(() => {
    if (area && point) setLastSearchArea({ b: area, lat: point.lat, lng: point.lng, where: query.where });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [areaKey, point?.lat, point?.lng, query.where]);

  const args =
    area && point && user !== undefined
      ? { lat: point.lat, lng: point.lng, b: area, kind: query.kind, q: query.q, only: query.only, hidden: query.hidden }
      : null;
  const userId = user?.id ?? null;
  const mapShowing = isDesktop === null ? false : isDesktop ? query.view !== "list" : query.view === "map";
  const search = useResults(userId, args, mapShowing);

  useEffect(() => {
    setResultsState({ origin: point, facets: search.facets });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [point?.lat, point?.lng, search.facets]);

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
    const b = await startArea(supabase, coords);
    const next = { ...query, lat: coords.lat, lng: coords.lng, b, where: CURRENT_LOCATION_LABEL };
    pushResults(resultsHref(next));
    reverseGeocode(coords).then((label) => {
      if (label && window.location.search.includes(`lat=${coords.lat.toFixed(5)}`)) {
        replaceResults(resultsHref({ ...next, where: label }));
      }
    });
  }

  // "Search this area": the map's view becomes the search area. Distances stay measured from
  // the place typed while it's still on the map; otherwise from the map's middle.
  const onMoved = useCallback((view: Box) => setMoved({ areaKey: areaKey ?? "", view }), [areaKey]);
  function searchBox(view: Box) {
    if (boxTooLarge(view)) return;
    const typed = query.lat !== null && query.lng !== null ? { lat: query.lat, lng: query.lng } : null;
    const keep = typed !== null && query.where !== MAP_AREA_LABEL && boxContains(view, typed);
    const from = keep && typed ? typed : boxCenter(view);
    pushResults(resultsHref({ ...query, b: view, lat: from.lat, lng: from.lng, where: keep ? query.where : MAP_AREA_LABEL }));
  }
  const movedView = moved && moved.areaKey === areaKey && !sameBox(moved.view, area) ? moved.view : null;

  const total = search.total;
  const capped = search.capped;
  const placeWord = (n: number) => (n === 1 ? "place" : "places");
  const whereWords = !query.where || query.where === MAP_AREA_LABEL ? " in this map area" : ` near ${query.where}`;
  const approximate = approxArea !== null && approxArea === areaKey;

  // ------------------------------------------------------------------ no area yet
  if (needsArea) {
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
          {search.error ?? "No places match. Try another kind, a larger map area, or turning a filter off."}
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

  const approximateNote = approximate && (
    <p className="text-[13px] text-muted">
      Approximate, from your internet connection.{" "}
      <button type="button" onClick={locateMe} disabled={geo.locating} className="font-medium text-link hover:underline disabled:opacity-50">
        {geo.locating ? "Finding your location…" : "Use my location"}
      </button>
    </p>
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
              {whereWords}
            </span>
          </>
        )}
      </p>
      {capped && (
        <p className="text-[13px] text-muted">The list shows the nearest 1,000. Zoom the map in, or pick a kind or a name, to narrow it.</p>
      )}
      {approximateNote}
      <SortMenu query={query} onChange={update} />
    </div>
  );

  const searchHereButton = (top: string) =>
    movedView && (
      <button
        type="button"
        onClick={() => searchBox(movedView)}
        disabled={boxTooLarge(movedView)}
        className={`absolute left-1/2 ${top} z-10 inline-flex h-10 -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full bg-white px-4 text-sm font-medium text-zinc-950 shadow-[0_2px_10px_rgba(0,0,0,0.16)] hover:bg-zinc-50 disabled:text-muted`}
      >
        <RefreshIcon />
        {boxTooLarge(movedView) ? "Zoom in to search this area" : "Search this area"}
      </button>
    );

  const map = (className: string, overlays: ReactNode, buttonTop = "top-3") => (
    <ResultsMap
      places={markers}
      cells={search.cells}
      area={area}
      highlightId={hoverId}
      onToggleStar={(id) => (userId ? search.toggleStar(id) : setJoinOpen(true))}
      onMoved={onMoved}
      onSearchBox={searchBox}
      className={className}
    >
      {overlays}
      {searchHereButton(buttonTop)}
      {approximate && !movedView && (
        <p className="absolute left-3 top-3 z-10 rounded-full bg-white/95 px-3 py-1.5 text-xs text-muted shadow-[0_2px_8px_rgba(0,0,0,0.12)]">
          Approximate, from your internet connection
        </p>
      )}
    </ResultsMap>
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
          {showMapOnPhone(query.view) ? (
            map("h-[calc(100dvh-230px)] w-full", null)
          ) : (
            <>
              {header}
              {list(false)}
            </>
          )}
          <button
            type="button"
            onClick={() => update({ view: showMapOnPhone(query.view) ? "list" : "map" })}
            className="fixed bottom-[92px] left-1/2 z-10 inline-flex h-12 -translate-x-1/2 items-center gap-2 rounded-full bg-primary px-5 text-[15px] font-medium text-white shadow-[0_4px_14px_rgba(0,0,0,0.25)]"
          >
            {showMapOnPhone(query.view) ? <ListIcon /> : <MapIcon />}
            {showMapOnPhone(query.view) ? "List" : "Map"}
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
                {map("h-full w-full", null)}
              </section>
            </div>
          )}
          {query.view === "map" && (
            <section aria-label="Map">
              {map(
                "h-[calc(100dvh-140px)] min-h-[480px] w-full",
                <p className="absolute left-1/2 top-3 z-10 -translate-x-1/2 whitespace-nowrap rounded-full bg-white/95 px-4 py-2 text-sm text-zinc-950 shadow-[0_2px_10px_rgba(0,0,0,0.12)]">
                  {search.loading && !search.results
                    ? "Searching…"
                    : `${(capped ? total : rows.length).toLocaleString("en-US")} ${placeWord(capped ? total : rows.length)}${whereWords}`}
                </p>,
                "top-16"
              )}
            </section>
          )}
        </div>
      )}

      <JoinNote open={joinOpen} onClose={() => setJoinOpen(false)} />
    </main>
  );
}

function showMapOnPhone(view: ResultsQuery["view"]) {
  return view === "map";
}
