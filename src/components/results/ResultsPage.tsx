"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SearchForm from "@/components/results/SearchForm";
import FilterBar, { SortMenu } from "@/components/results/FilterBar";
import FiltersSheet from "@/components/results/FiltersSheet";
import type { DrawState } from "@/components/results/ResultsMap";
import AllFiltersPanel, { type ListOption } from "@/components/results/AllFiltersPanel";
import MoreChips from "@/components/results/MoreChips";
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
  DRAWN_AREA_LABEL,
  MAP_AREA_LABEL,
  moreArg,
  parseResultsQuery,
  resultsHref,
  sameBox,
  shapeBox,
  shapeCenter,
  type Box,
  type ResultsQuery,
} from "@/lib/resultsQuery";
import type { Facets } from "@/lib/searchTypes";
import { CURRENT_LOCATION_LABEL, getLastSearchArea, setLastSearchArea } from "@/lib/lastSearchCoords";
import { geocodeLocationText } from "@/lib/locationLookup";
import { startArea } from "@/lib/searchArea";
import { fetchIpArea } from "@/lib/ipArea";
import { pushResults, replaceResults } from "@/lib/resultsNav";
import { placeIdFromPath, setSheetStart } from "@/lib/placePanel";
import { topLevelTypeForCategoryPaths, typeForPath, TYPE_OPTIONS } from "@/lib/entityTypes";
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

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M21 21l-6 -6" />
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
// Shown once a search has been out for a few seconds (useResults' slow).
const STILL_SEARCHING = "Still searching… A big area takes longer the first time.";

export default function ResultsPage() {
  const router = useRouter();
  const pathname = usePathname();
  const liveParams = useSearchParams().toString();
  // While a place panel is open the address is the place's own (/venue/<id>) and this page
  // stays behind it; its search is the one from before the panel opened.
  const onResults = pathname === "/";
  const [keptParams, setKeptParams] = useState(liveParams);
  if (onResults && keptParams !== liveParams) setKeptParams(liveParams);
  const paramsText = onResults ? liveParams : keptParams;
  const query = useMemo(() => parseResultsQuery(new URLSearchParams(paramsText)), [paramsText]);
  const selectedId = placeIdFromPath(pathname);
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [joinOpen, setJoinOpen] = useState(false);
  // Phone: the full-screen search and the filters sheet.
  const [searching, setSearching] = useState(false);
  const [filtersOpen, setFiltersOpen] = useState(false);
  // Computer: All filters, in place of the list.
  const [panelOpen, setPanelOpen] = useState(false);
  // The person's own lists, for "On one of your lists" (not Want to try, which has its own).
  const [lists, setLists] = useState<ListOption[]>([]);
  // Drawing an area on the map (null: not drawing), and how many places the shape holds.
  const [draw, setDraw] = useState<DrawState | null>(null);
  const [drawCount, setDrawCount] = useState<{ key: string; n: number | null } | null>(null);
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

  const update = useCallback(
    (patch: Partial<ResultsQuery>) => replaceResults(resultsHref({ ...query, ...patch })),
    [query]
  );

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
    // A drawn area isn't kept: coming back opens on the box around it, as a map area.
    if (area && point) {
      setLastSearchArea({ b: area, lat: point.lat, lng: point.lng, where: query.where === DRAWN_AREA_LABEL ? MAP_AREA_LABEL : query.where });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [areaKey, point?.lat, point?.lng, query.where]);

  const args =
    area && point && user !== undefined
      ? { lat: point.lat, lng: point.lng, b: area, kind: query.kind, q: query.q, only: query.only, hidden: query.hidden, more: query.more }
      : null;
  const userId = user?.id ?? null;

  const wantLists = userId !== null && (panelOpen || filtersOpen || query.more.list !== null);
  useEffect(() => {
    if (!wantLists || !userId) return;
    let cancelled = false;
    supabase
      .from("lists")
      .select("id, name, is_default_list")
      .eq("owner_id", userId)
      .order("name")
      .then(({ data }) => {
        if (cancelled) return;
        const rows = (data ?? []) as { id: string; name: string; is_default_list: boolean }[];
        setLists(rows.filter((l) => !l.is_default_list).map((l) => ({ id: l.id, name: l.name })));
      });
    return () => {
      cancelled = true;
    };
  }, [wantLists, userId, supabase]);

  // "Can't remember the name?" in the What box opens the filters here.
  useEffect(() => {
    function open() {
      if (isDesktop) setPanelOpen(true);
      else setFiltersOpen(true);
    }
    window.addEventListener("sms:open-filters", open);
    return () => window.removeEventListener("sms:open-filters", open);
  }, [isDesktop]);

  // Escape closes All filters.
  useEffect(() => {
    if (!panelOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !document.querySelector("[role=dialog]")) setPanelOpen(false);
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [panelOpen]);
  const mapShowing = isDesktop === null ? false : isDesktop ? query.view !== "list" : query.view === "map";
  const search = useResults(userId, args, mapShowing);

  useEffect(() => {
    setResultsState({ origin: point, facets: search.facets, query });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [point?.lat, point?.lng, search.facets, paramsText]);
  // The header's search boxes show this search while a place panel is open over it.
  useEffect(() => () => setResultsState({ query: null }), []);

  // Opening a place: its panel over this page (the address becomes the place's link). With a
  // panel already open, the next place replaces it, so Close and Back return to the results.
  // On a phone the sheet opens as a short card over the map, or at full height over the list.
  const openPlace = useCallback(
    (id: string) => {
      setSheetStart(isDesktop === false && query.view === "map" ? "peek" : "full");
      if (selectedId) router.replace(`/venue/${id}`, { scroll: false });
      else router.push(`/venue/${id}`, { scroll: false });
    },
    [isDesktop, query.view, selectedId, router]
  );

  // The open place's row: keep it in view in the list.
  const listRef = useRef<HTMLUListElement>(null);
  useEffect(() => {
    if (!selectedId) return;
    const row = listRef.current?.querySelector(`[data-place-id="${selectedId}"]`);
    row?.scrollIntoView({ block: "nearest" });
  }, [selectedId]);

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

  // Counts for a search in the same map area, with the All filters panel's own counts (streets,
  // chain or independent, website, phone, closed places): the panel and the filters sheet.
  const countFor = useCallback(
    async (q: ResultsQuery): Promise<Facets | null> => {
      const box = q.b ?? area;
      if (!box) return null;
      const { data, error } = await supabase.rpc("area_facets", {
        west: box.west,
        south: box.south,
        east: box.east,
        north: box.north,
        type_key: typeForPath(q.kind),
        cuisine_path: q.kind && q.kind.includes(".") ? q.kind : null,
        name_query: q.q.trim() || null,
        only_favorites: q.only.includes("favorites"),
        only_friends: q.only.includes("friends"),
        only_want: q.only.includes("want"),
        show_hidden: q.hidden,
        more: moreArg(q.more, true),
      });
      return error ? null : (data as Facets);
    },
    [area, supabase]
  );

  // Computer, All filters open: the panel and the map beside it fill the window below the bar,
  // so "Show N places" at the panel's foot is always in view.
  const panelRowRef = useRef<HTMLDivElement>(null);
  const [panelTop, setPanelTop] = useState(220);
  useEffect(() => {
    if (!panelOpen) return;
    function measure() {
      const el = panelRowRef.current;
      if (el) setPanelTop(Math.round(el.getBoundingClientRect().top + window.scrollY));
    }
    const frame = requestAnimationFrame(measure);
    window.addEventListener("resize", measure);
    const observer = typeof ResizeObserver !== "undefined" ? new ResizeObserver(measure) : null;
    const top = document.querySelector("[data-place-panel-top]");
    if (observer && top) observer.observe(top);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", measure);
      observer?.disconnect();
    };
  }, [panelOpen]);

  // Phone map: it fills the screen below the filters, and the tab bar steps aside for it
  // (globals.css), so the map has the whole height.
  const phoneMap = isDesktop === false && !needsArea && showMapOnPhone(query.view);
  const phoneMapRef = useRef<HTMLDivElement>(null);
  const [phoneMapTop, setPhoneMapTop] = useState(210);
  useEffect(() => {
    if (!phoneMap) return;
    const root = document.documentElement;
    root.dataset.fullMap = "1";
    function measure() {
      const el = phoneMapRef.current;
      if (el) setPhoneMapTop(Math.round(el.getBoundingClientRect().top + window.scrollY));
    }
    const frame = requestAnimationFrame(measure);
    window.addEventListener("resize", measure);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("resize", measure);
      delete root.dataset.fullMap;
    };
  }, [phoneMap]);

  async function locateMe() {
    const coords = await geo.requestLocation();
    if (!coords) return;
    const b = await startArea(supabase, coords);
    const next = { ...query, lat: coords.lat, lng: coords.lng, b, where: CURRENT_LOCATION_LABEL, more: { ...query.more, area: null } };
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
    const drawn = query.where === DRAWN_AREA_LABEL;
    pushResults(
      resultsHref({
        ...query,
        b: view,
        lat: from.lat,
        lng: from.lng,
        where: keep && !drawn ? query.where : MAP_AREA_LABEL,
        more: { ...query.more, area: null },
      })
    );
  }

  // ------------------------------------------------------------------ drawing an area
  // Starts drawing on the map: the filters close, and the map shows (Map view on a phone; Split
  // on a computer if the list was showing alone).
  // patch: choices to apply on the way (the phone's filters sheet), in the same change.
  const startDraw = useCallback(
    (patch: Partial<ResultsQuery> = {}) => {
      setPanelOpen(false);
      setFiltersOpen(false);
      const view = isDesktop === false && query.view !== "map" ? "map" : isDesktop && query.view === "list" ? "split" : null;
      if (view || Object.keys(patch).length) update({ ...patch, ...(view ? { view } : {}) });
      setDraw({ points: [], closed: false });
    },
    [isDesktop, query.view, update]
  );
  const drawKey = draw && draw.closed ? JSON.stringify(draw.points) : null;
  const drawBox = draw && draw.closed && draw.points.length >= 3 ? shapeBox(draw.points) : null;
  const drawTooLarge = drawBox ? boxTooLarge(drawBox) : false;
  useEffect(() => {
    if (!drawKey || !draw || drawTooLarge) return;
    let cancelled = false;
    const points = draw.points;
    const t = setTimeout(() => {
      countFor({ ...query, b: shapeBox(points), more: { ...query.more, area: points } }).then((f) => {
        if (!cancelled) setDrawCount({ key: drawKey, n: f?.total ?? null });
      });
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
    // The shape is captured through drawKey; the other filters through paramsText.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [drawKey, drawTooLarge, paramsText]);
  const shownDrawCount = drawCount && drawCount.key === drawKey ? drawCount.n : null;
  function finishDraw() {
    if (!draw || !draw.closed || draw.points.length < 3 || drawTooLarge) return;
    const points = draw.points;
    const b = shapeBox(points);
    const typed = query.lat !== null && query.lng !== null ? { lat: query.lat, lng: query.lng } : null;
    const from = typed && boxContains(b, typed) ? typed : shapeCenter(points);
    pushResults(resultsHref({ ...query, b, lat: from.lat, lng: from.lng, where: DRAWN_AREA_LABEL, more: { ...query.more, area: points } }));
    setDraw(null);
  }
  const movedView = moved && moved.areaKey === areaKey && !sameBox(moved.view, area) ? moved.view : null;

  const total = search.total;
  const capped = search.capped;
  const placeWord = (n: number) => (n === 1 ? "place" : "places");
  const whereWords =
    !query.where || query.where === MAP_AREA_LABEL
      ? " in this map area"
      : query.where === DRAWN_AREA_LABEL
        ? " in your drawn area"
        : ` near ${query.where}`;
  const approximate = approxArea !== null && approxArea === areaKey;
  const closeSearch = useCallback(() => setSearching(false), []);

  // Phone: what's being searched, in one line; tapping it opens the full-screen search.
  const summaryTitle = query.q ? `“${query.q}”` : query.kind ? kindName(query.kind) : "Search places to eat and drink";
  const summaryWhere = needsArea
    ? "Pick a town, or use your location"
    : !query.where || query.where === MAP_AREA_LABEL || query.where === DRAWN_AREA_LABEL
      ? query.where === DRAWN_AREA_LABEL ? "Drawn area" : "Map area"
      : approximate
        ? `Around ${query.where}`
        : `Near ${query.where}`;
  const phoneSummary = (
    <div className="border-b border-line px-4 py-3 md:hidden">
      <button
        type="button"
        onClick={() => setSearching(true)}
        className="flex h-14 w-full items-center gap-3 rounded-full border border-[#dddddd] bg-white px-4 text-left shadow-[0_2px_10px_rgba(0,0,0,0.08)]"
      >
        <span className="text-zinc-950">
          <SearchIcon />
        </span>
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-[15px] font-medium text-zinc-950">{summaryTitle}</span>
          <span className="truncate text-[13px] text-muted">{summaryWhere}</span>
        </span>
        <span className="sr-only">, change search</span>
      </button>
      {searching && <SearchForm layout="screen" onClose={closeSearch} />}
    </div>
  );

  // ------------------------------------------------------------------ no area yet
  if (needsArea) {
    return (
      <main className="flex flex-1 flex-col">
        {phoneSummary}
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
      {search.error && !search.loading ? (
        <div className="flex flex-col items-center gap-3 px-6 py-10 text-center text-sm text-muted" role="alert">
          <p>{search.error.message}</p>
          <button
            type="button"
            onClick={search.retry}
            className="rounded-full border border-line px-4 py-2 text-[15px] font-medium text-zinc-950 hover:bg-zinc-50"
          >
            Try again
          </button>
        </div>
      ) : search.loading && !search.results ? (
        <p className="px-6 py-10 text-center text-sm text-muted">{search.slow ? STILL_SEARCHING : "Searching…"}</p>
      ) : rows.length === 0 ? (
        <div className="px-6 py-10 text-center text-sm text-muted">
          No places match. Try another kind, a larger map area, or turning a filter off.
        </div>
      ) : (
        // While a new search is out, the last answer stays (dimmed) so the page doesn't jump.
        <ul
          ref={listRef}
          className={`${card ? "grid gap-3 px-4 py-3 md:px-6 lg:grid-cols-2" : ""} transition-opacity ${search.loading ? "opacity-40" : ""}`}
          aria-busy={search.loading}
        >
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
              highlighted={hoverId === r.id || selectedId === r.id}
              selected={selectedId === r.id}
              onOpen={openPlace}
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
        {userId && query.hidden && (
          <p>
            <button type="button" onClick={() => update({ hidden: false })} className="font-medium text-zinc-950 underline">
              Leave out places you hid
            </button>
            {" · "}
            <Link href="/hidden" className="font-medium text-zinc-950 underline">
              All your hidden places
            </Link>
          </p>
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
        {search.loading ? (
          search.slow ? STILL_SEARCHING : "Searching…"
        ) : search.error ? (
          <>
            <span className="font-medium">The search didn’t finish</span>
            <span className="text-muted">
              {query.q ? ` for “${query.q}”` : ""}
              {whereWords}
            </span>
          </>
        ) : (
          <>
            <span className="font-medium">
              {capped
                ? `Nearest ${(search.results?.length ?? 0).toLocaleString("en-US")} of ${total.toLocaleString("en-US")} places`
                : `${rows.length.toLocaleString("en-US")} ${placeWord(rows.length)}`}
            </span>
            <span className="text-muted">
              {query.q ? ` for “${query.q}”` : ""}
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

  // While drawing: what to do, how many places the shape holds, and Start over / Cancel / Done.
  const touch = isDesktop === false;
  const drawBar = draw && (
    <>
      <div
        role="region"
        aria-label="Drawing an area"
        className={`absolute z-10 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-[14px] bg-white py-2 pl-4 pr-2 shadow-[0_2px_14px_rgba(0,0,0,0.18)] ${
          touch ? "inset-x-2 top-2" : "left-1/2 top-3 max-w-[calc(100%-120px)] -translate-x-1/2"
        }`}
      >
        <p className="min-w-0 flex-1 text-sm text-zinc-950" aria-live="polite">
          {!draw.closed ? (
            touch ? (
              "Draw around the area with your finger"
            ) : draw.points.length < 3 ? (
              "Click to drop points around the part of town you mean."
            ) : (
              "Click the first point again, or double-click, to close the shape."
            )
          ) : drawTooLarge ? (
            <span className="font-medium text-red-700">That area is too large to search. Draw a smaller one.</span>
          ) : (
            <>
              <span className="font-medium">
                {shownDrawCount === null ? "Counting…" : `${shownDrawCount.toLocaleString("en-US")} ${placeWord(shownDrawCount)} in your area.`}
              </span>{" "}
              {!touch && <span className="text-muted">Drag a point to change the shape.</span>}
            </>
          )}
        </p>
        {!touch && (
          <div className="flex items-center gap-1.5">
            {draw.points.length > 0 && (
              <button type="button" onClick={() => setDraw({ points: [], closed: false })} className="h-10 rounded-[10px] border border-[#dddddd] px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50">
                Start over
              </button>
            )}
            <button type="button" onClick={() => setDraw(null)} className="h-10 rounded-[10px] px-3 text-sm font-medium text-zinc-950 hover:bg-zinc-100">
              Cancel
            </button>
            <button
              type="button"
              onClick={finishDraw}
              disabled={!draw.closed || drawTooLarge}
              className="h-10 rounded-[10px] bg-primary px-[18px] text-sm font-medium text-white hover:bg-primary-hover disabled:opacity-40"
            >
              Done
            </button>
          </div>
        )}
        {touch && (
          <button type="button" aria-label="Cancel drawing" onClick={() => setDraw(null)} className="flex h-11 w-11 items-center justify-center rounded-[10px] text-zinc-950">
            <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
              <path d="M18 6l-12 12M6 6l12 12" />
            </svg>
          </button>
        )}
      </div>
      {touch && draw.closed && (
        <div className="absolute inset-x-0 bottom-0 z-10 flex gap-2.5 rounded-t-[20px] bg-white px-4 pb-7 pt-4 shadow-[0_-4px_18px_rgba(0,0,0,0.14)]">
          <button type="button" onClick={() => setDraw({ points: [], closed: false })} className="h-[52px] flex-1 rounded-xl border border-[#dddddd] text-base font-medium text-zinc-950">
            Start over
          </button>
          <button
            type="button"
            onClick={finishDraw}
            disabled={drawTooLarge}
            className="h-[52px] flex-[1.3] rounded-xl bg-primary text-base font-medium text-white disabled:opacity-40"
          >
            Done
          </button>
        </div>
      )}
    </>
  );

  const map = (className: string, overlays: ReactNode, buttonTop = "top-3") => (
    <ResultsMap
      places={markers}
      cells={search.cells}
      area={area}
      highlightId={hoverId}
      selectedId={selectedId}
      onSelect={openPlace}
      revealInset={isDesktop ? { right: 440, bottom: 0 } : { right: 0, bottom: Math.round((typeof window === "undefined" ? 800 : window.innerHeight) * 0.46) }}
      onMoved={onMoved}
      onSearchBox={searchBox}
      shape={query.more.area}
      draw={draw}
      onDraw={setDraw}
      className={className}
    >
      {draw ? drawBar : overlays}
      {!draw && searchHereButton(buttonTop)}
      {approximate && !movedView && (
        <p className="absolute left-3 top-3 z-10 rounded-full bg-white/95 px-3 py-1.5 text-xs text-muted shadow-[0_2px_8px_rgba(0,0,0,0.12)]">
          Approximate, from your internet connection
        </p>
      )}
    </ResultsMap>
  );

  return (
    <main className="flex flex-1 flex-col">
      {phoneSummary}
      <div data-place-panel-top>
        <FilterBar
          query={query}
          facets={search.facets}
          signedIn={Boolean(userId)}
          kindName={kindName}
          onChange={update}
          onLocked={() => setJoinOpen(true)}
          onOpenFilters={isDesktop === false ? () => setFiltersOpen(true) : undefined}
          onTogglePanel={isDesktop ? () => setPanelOpen((o) => !o) : undefined}
          panelOpen={panelOpen}
        />
        <MoreChips query={query} lists={lists} signedIn={Boolean(userId)} onChange={update} />
      </div>
      {filtersOpen && (
        <FiltersSheet
          query={query}
          facets={search.facets}
          signedIn={Boolean(userId)}
          lists={lists}
          countFor={countFor}
          onApply={update}
          onLocked={() => setJoinOpen(true)}
          onClose={() => setFiltersOpen(false)}
          onDraw={startDraw}
        />
      )}

      {/* Phone: one view at a time, with a button to switch. */}
      {isDesktop === false && (
        <div>
          {phoneMap ? (
            <div ref={phoneMapRef} style={{ height: `calc(100dvh - ${phoneMapTop}px)` }}>
              {map("h-full w-full", null)}
            </div>
          ) : (
            <>
              {header}
              {list(false)}
            </>
          )}
          {!draw && <button
            type="button"
            onClick={() => update({ view: showMapOnPhone(query.view) ? "list" : "map" })}
            className={`fixed ${phoneMap || !userId ? "bottom-6" : "bottom-[92px]"} left-1/2 z-10 inline-flex h-12 -translate-x-1/2 items-center gap-2 rounded-full bg-primary px-5 text-[15px] font-medium text-white shadow-[0_4px_14px_rgba(0,0,0,0.25)]`}
          >
            {showMapOnPhone(query.view) ? <ListIcon /> : <MapIcon />}
            {showMapOnPhone(query.view) ? "List" : "Map"}
          </button>}
        </div>
      )}

      {/* Computer: All filters in place of the list, with the map (or, in List view, the list)
          beside it. */}
      {isDesktop && panelOpen && (
        <div ref={panelRowRef} className="flex" style={{ height: `max(480px, calc(100dvh - ${panelTop}px))` }}>
          <section aria-label="Filters" className="h-full w-[480px] shrink-0 border-r border-line">
            <AllFiltersPanel
              query={query}
              facets={search.facets}
              signedIn={Boolean(userId)}
              lists={lists}
              total={search.loading ? null : capped ? total : rows.length}
              countFor={countFor}
              onChange={update}
              onLocked={() => setJoinOpen(true)}
              onClose={() => setPanelOpen(false)}
              onDraw={() => startDraw()}
            />
          </section>
          {query.view === "list" ? (
            <section aria-label="Results" className="h-full min-w-0 flex-1 overflow-y-auto">
              {header}
              {list(false)}
            </section>
          ) : (
            <section aria-label="Map" className="h-full min-w-0 flex-1">
              {map(
                "h-full w-full",
                <p className="absolute left-1/2 top-3 z-10 -translate-x-1/2 whitespace-nowrap rounded-full bg-white/95 px-4 py-2 text-sm font-medium text-zinc-950 shadow-[0_2px_10px_rgba(0,0,0,0.12)]">
                  {search.loading
                    ? search.slow
                      ? "Still searching…"
                      : "Searching…"
                    : search.error
                      ? "The search didn’t finish"
                      : `${(capped ? total : rows.length).toLocaleString("en-US")} ${placeWord(capped ? total : rows.length)} match`}
                </p>,
                "top-16"
              )}
            </section>
          )}
        </div>
      )}

      {/* Computer: List, Split or Map. */}
      {isDesktop && !panelOpen && (
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
                  {search.loading
                    ? search.slow
                      ? "Still searching…"
                      : "Searching…"
                    : search.error
                      ? "The search didn’t finish"
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
