"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import LocationInput from "@/components/LocationInput";
import WhatBox from "@/components/results/WhatBox";
import { useGeolocation } from "@/lib/useGeolocation";
import { geocodeLocationText } from "@/lib/locationLookup";
import { reverseGeocode } from "@/lib/reverseGeocode";
import { addSearchHistory } from "@/lib/searchHistory";
import { CURRENT_LOCATION_LABEL, getLastSearchCoords, type Coords } from "@/lib/lastSearchCoords";
import { emptyQuery, MAP_AREA_LABEL, parseResultsQuery, resultsHref, type ResultsQuery } from "@/lib/resultsQuery";
import { useResultsState } from "@/lib/resultsStore";
import { startArea } from "@/lib/searchArea";
import { pushResults, replaceResults } from "@/lib/resultsNav";
import { TYPE_OPTIONS } from "@/lib/entityTypes";
import { createClient } from "@/lib/supabase/client";

type Layout = "bar" | "stacked" | "screen";

function PinIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 11a3 3 0 1 0 6 0a3 3 0 0 0 -6 0M17.657 16.657l-4.243 4.243a2 2 0 0 1 -2.827 0l-4.244 -4.243a8 8 0 1 1 11.314 0z" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M21 21l-6 -6" />
    </svg>
  );
}

function LocateIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M21 3l-6.5 18a.55 .55 0 0 1 -1 0l-3.5 -7l-7 -3.5a.55 .55 0 0 1 0 -1l18 -6.5" />
    </svg>
  );
}

// Shown in the Search button while a search is being worked out.
function Spinner() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" className="animate-spin motion-reduce:animate-none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.3" strokeWidth="2.5" />
      <path d="M21 12a9 9 0 0 0 -9 -9" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  );
}

function BackIcon() {
  return (
    <svg viewBox="0 0 24 24" width={24} height={24} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M5 12h14M5 12l6 6M5 12l6 -6" />
    </svg>
  );
}

// The What and Where boxes: in the header on a computer ("bar"), or the phone's full-screen
// search ("screen", opened from the summary at the top of the results page). Searching opens
// the results page with the search in its address. ("stacked" is the two boxes one above the
// other, without the screen around them.)
export default function SearchForm({ layout, onClose }: { layout: Layout; onClose?: () => void }) {
  const pathname = usePathname();
  const params = useSearchParams();
  // On the results page, its search; with a place panel open over it, the search behind.
  const { query: behind } = useResultsState();
  const current = pathname === "/" ? parseResultsQuery(params) : (behind ?? emptyQuery());
  // Starts again from the address whenever the search there changes (Back, a new search).
  // The results page is showing, or is behind an open place panel: change its address in place.
  const onResultsPage = pathname === "/" || behind !== null;
  return (
    <SearchFormInner key={`${current.q}|${current.where}`} layout={layout} current={current} onResultsPage={onResultsPage} onClose={onClose} />
  );
}

function SearchFormInner({
  layout,
  current,
  onResultsPage,
  onClose,
}: {
  layout: Layout;
  current: ResultsQuery;
  onResultsPage: boolean;
  onClose?: () => void;
}) {
  const router = useRouter();
  // Already on the results page: change its address in place (src/lib/resultsNav.ts).
  // Elsewhere: go to it.
  // The phone's search screen closes once the search is made.
  const go = (href: string) => {
    if (onResultsPage) pushResults(href);
    else router.push(href);
    onClose?.();
  };
  const supabase = useMemo(() => createClient(), []);
  const { origin, facets } = useResultsState();
  const [what, setWhat] = useState(current.q);
  const [where, setWhere] = useState(current.where);
  const [error, setError] = useState<string | null>(null);
  // While a search is being worked out (finding the place typed, sizing the area): the Search
  // button shows a spinner, and a second Enter or pick doesn't start another one.
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  const geo = useGeolocation();
  // Where the phone's search screen lists the What box's suggestions.
  const [listEl, setListEl] = useState<HTMLElement | null>(null);

  // The search screen: the page behind it stays still, and Escape closes it.
  useEffect(() => {
    if (layout !== "screen") return;
    const before = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose?.();
    }
    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = before;
      document.removeEventListener("keydown", onKey);
    };
  }, [layout, onClose]);

  const here: Coords | null = current.lat !== null && current.lng !== null ? { lat: current.lat, lng: current.lng } : null;
  const near = origin ?? here ?? getLastSearchCoords();

  // The point and area to search for what's in the Where box (or the text just picked there),
  // or null if it can't be found. Unchanged text keeps the current area; a new place opens on
  // that place (a town on the whole town, an address on about the nearest 50 places).
  async function resolveWhere(picked?: string): Promise<Pick<ResultsQuery, "where" | "lat" | "lng" | "b"> | null> {
    const text = (picked ?? where).trim();
    const unchanged = text === "" || text === current.where || text === CURRENT_LOCATION_LABEL || text === MAP_AREA_LABEL;
    if (unchanged && here && current.b) {
      return { where: current.where || text, lat: here.lat, lng: here.lng, b: current.b };
    }
    if (text === "" || text === MAP_AREA_LABEL) return { where: "", lat: null, lng: null, b: null };
    const found = await geocodeLocationText(text, near);
    if (!found) {
      setError("We couldn't find that place. Try a city, town or ZIP code.");
      return null;
    }
    addSearchHistory(text);
    const b = await startArea(supabase, found, { radiusMiles: found.radiusMiles, minPlaces: found.minPlaces });
    return { where: text, lat: found.lat, lng: found.lng, b };
  }

  // Searches with the boxes as they are (or with the Where text just picked).
  async function search(patch: Partial<ResultsQuery>, pickedWhere?: string) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      const point = await resolveWhere(pickedWhere);
      if (!point) return;
      go(resultsHref({ ...current, ...point, ...patch }));
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault();
    void search({ q: what });
  }

  async function locateMe() {
    setError(null);
    const coords = await geo.requestLocation();
    if (!coords) return;
    setWhere(CURRENT_LOCATION_LABEL);
    const b = await startArea(supabase, coords);
    const next: ResultsQuery = { ...current, q: what, where: CURRENT_LOCATION_LABEL, lat: coords.lat, lng: coords.lng, b };
    go(resultsHref(next));
    // A place name for the box when the lookup answers; the search doesn't wait for it.
    reverseGeocode(coords).then((label) => {
      if (label && window.location.pathname === "/" && window.location.search.includes(`lat=${coords.lat.toFixed(5)}`)) {
        replaceResults(resultsHref({ ...next, where: label }));
      }
    });
  }

  const box = "flex h-[46px] min-w-0 items-center gap-2 rounded-[10px] border border-[#dddddd] bg-white px-3 focus-within:border-zinc-500";
  const input = "w-full min-w-0 bg-transparent text-[15px] text-zinc-950 placeholder:text-zinc-500 focus:outline-none";
  const whatId = `what-${layout}`;
  const whereId = `where-${layout}`;

  if (layout === "screen") {
    const row = "flex h-[52px] min-w-0 items-center gap-2.5 px-3.5";
    const field = "w-full min-w-0 bg-transparent text-base text-zinc-950 placeholder:text-zinc-500 focus:outline-none";
    return (
      <div role="dialog" aria-modal="true" aria-label="Search" className="fixed inset-0 z-50 flex flex-col bg-white md:hidden">
        <form role="search" aria-label="Find places" onSubmit={handleSubmit} className="flex items-start gap-1 border-b border-line py-3 pl-1.5 pr-4">
          <button type="button" aria-label="Back" onClick={onClose} className="flex h-[52px] w-11 shrink-0 items-center justify-center text-zinc-950">
            <BackIcon />
          </button>
          <div className="min-w-0 flex-1 rounded-2xl border border-[#dddddd] bg-white shadow-[0_2px_10px_rgba(0,0,0,0.06)]">
            <div className={row}>
              <span className="text-zinc-500">
                <SearchIcon />
              </span>
              <label htmlFor={whatId} className="sr-only">
                What
              </label>
              <WhatBox
                id={whatId}
                value={what}
                onChange={setWhat}
                onPickKind={(path) => {
                  setWhat("");
                  void search({ q: "", kind: path });
                }}
                onPickPlace={(id) => {
                  onClose?.();
                  router.push(`/venue/${id}`);
                }}
                onSubmitText={() => void search({ q: what })}
                near={near}
                facets={facets}
                inputClassName={field}
                autoFocus
                listTarget={listEl}
              />
              {what && (
                <button
                  type="button"
                  aria-label="Clear"
                  onClick={() => {
                    setWhat("");
                    document.getElementById(whatId)?.focus();
                  }}
                  className="-mr-1.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-zinc-500"
                >
                  <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
                    <path d="M18 6l-12 12M6 6l12 12" />
                  </svg>
                </button>
              )}
            </div>
            <div className="mx-3.5 h-px bg-line" />
            <div className={row}>
              <span className="text-zinc-500">
                <PinIcon />
              </span>
              <label htmlFor={whereId} className="sr-only">
                Where
              </label>
              <LocationInput
                id={whereId}
                value={where}
                onChange={(v) => {
                  geo.setGeoError(null);
                  setWhere(v);
                }}
                onUseMyLocation={locateMe}
                onPick={(label) => void search({ q: what }, label)}
                locating={geo.locating}
                near={near}
                inputClassName={field}
                hideLocateButton
              />
              <button
                type="button"
                onClick={locateMe}
                disabled={geo.locating}
                aria-label={geo.locating ? "Finding your location…" : "Use my location"}
                className="-mr-1.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-link disabled:opacity-50"
              >
                <LocateIcon />
              </button>
            </div>
          </div>
          <button type="submit" className="sr-only">
            Search
          </button>
        </form>
        {(error || geo.geoError) && (
          <p role="alert" className="px-4 pt-3 text-sm text-red-700">
            {error || geo.geoError}
          </p>
        )}
        <div className="min-h-0 flex-1 overflow-y-auto">
          <div ref={setListEl} />
          {/* Nothing typed yet: the four types, with how many are in the area searched. */}
          {!what.trim() && (
            <div className="py-1">
              <p className="px-4 pb-1 pt-3 text-[13px] font-medium text-muted">Kinds of places</p>
              {TYPE_OPTIONS.filter((t) => t.key !== "all").map((t) => {
                const n = facets?.types[t.key];
                return (
                  <button
                    key={t.key}
                    type="button"
                    onClick={() => void search({ q: "", kind: t.key })}
                    className="flex min-h-14 w-full items-center gap-3 px-4 py-2 text-left text-[15px]"
                  >
                    <span className="flex-1 font-medium text-link">{t.label}</span>
                    {n !== undefined && <span className="text-[13px] text-muted">{n.toLocaleString("en-US")} nearby</span>}
                  </button>
                );
              })}
            </div>
          )}
        </div>
        <div className="border-t border-line px-4 pb-6 pt-3">
          <button
            type="button"
            onClick={() => void search({ q: what })}
            disabled={busy}
            aria-busy={busy}
            className="flex h-[52px] w-full items-center justify-center gap-2 rounded-xl bg-primary text-base font-medium text-white disabled:opacity-80"
          >
            {busy && <Spinner />}
            {busy ? "Searching…" : "Search"}
          </button>
        </div>
      </div>
    );
  }

  return (
    <form
      role="search"
      aria-label="Find places"
      onSubmit={handleSubmit}
      className={layout === "bar" ? "relative flex min-w-0 flex-1 gap-2" : "relative flex flex-col gap-2"}
    >
      <div className={`${box} ${layout === "bar" ? "flex-[1.2]" : ""}`}>
        <span className="text-zinc-500">
          <SearchIcon />
        </span>
        <label htmlFor={whatId} className="sr-only">
          What
        </label>
        <WhatBox
          id={whatId}
          value={what}
          onChange={setWhat}
          onPickKind={(path) => {
            setWhat("");
            void search({ q: "", kind: path });
          }}
          onPickPlace={(id) => router.push(`/venue/${id}`)}
          onSubmitText={() => void search({ q: what })}
          near={near}
          facets={facets}
          inputClassName={input}
        />
      </div>
      <div className={`${box} ${layout === "bar" ? "flex-1" : ""}`}>
        <span className="text-zinc-500">
          <PinIcon />
        </span>
        <label htmlFor={whereId} className="sr-only">
          Where
        </label>
        <LocationInput
          id={whereId}
          value={where}
          onChange={(v) => {
            geo.setGeoError(null);
            setWhere(v);
          }}
          onUseMyLocation={locateMe}
          onPick={(label) => void search({ q: what }, label)}
          locating={geo.locating}
          near={near}
          inputClassName={input}
          hideLocateButton
        />
        <button
          type="button"
          onClick={locateMe}
          disabled={geo.locating}
          aria-label={geo.locating ? "Finding your location…" : "Use my location"}
          className="-mr-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-link hover:bg-[#eef2fb] disabled:opacity-50"
        >
          <LocateIcon />
        </button>
      </div>
      {/* Enter in either box searches too, and picking a suggestion searches straight away. */}
      <button
        type="submit"
        disabled={busy}
        aria-busy={busy}
        aria-label={busy ? "Searching…" : "Search"}
        className="flex h-[46px] shrink-0 items-center justify-center gap-2 rounded-[10px] bg-primary px-3.5 text-[15px] font-medium text-white hover:opacity-90 disabled:opacity-80 xl:px-4"
      >
        {busy ? <Spinner /> : <SearchIcon />}
        <span className="hidden xl:inline" aria-hidden="true">
          Search
        </span>
      </button>
      {(error || geo.geoError) && (
        <p role="alert" className={`text-sm text-red-700 ${layout === "bar" ? "absolute left-0 top-full mt-1 rounded bg-white px-2 py-1 shadow" : ""}`}>
          {error || geo.geoError}
        </p>
      )}
    </form>
  );
}
