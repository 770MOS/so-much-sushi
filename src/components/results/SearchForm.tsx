"use client";

import { useMemo, useState, type FormEvent } from "react";
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
import { createClient } from "@/lib/supabase/client";

type Layout = "bar" | "stacked";

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

// The What and Where boxes: in the header on a computer ("bar"), at the top of the results
// page on a phone ("stacked"). Searching opens the results page with the search in its address.
export default function SearchForm({ layout }: { layout: Layout }) {
  const pathname = usePathname();
  const params = useSearchParams();
  const current = pathname === "/" ? parseResultsQuery(params) : emptyQuery();
  // Starts again from the address whenever the search there changes (Back, a new search).
  return <SearchFormInner key={`${current.q}|${current.where}`} layout={layout} current={current} onResultsPage={pathname === "/"} />;
}

function SearchFormInner({ layout, current, onResultsPage }: { layout: Layout; current: ResultsQuery; onResultsPage: boolean }) {
  const router = useRouter();
  // Already on the results page: change its address in place (src/lib/resultsNav.ts).
  // Elsewhere: go to it.
  const go = (href: string) => (onResultsPage ? pushResults(href) : router.push(href));
  const supabase = useMemo(() => createClient(), []);
  const { origin, facets } = useResultsState();
  const [what, setWhat] = useState(current.q);
  const [where, setWhere] = useState(current.where);
  const [error, setError] = useState<string | null>(null);
  const geo = useGeolocation();

  const here: Coords | null = current.lat !== null && current.lng !== null ? { lat: current.lat, lng: current.lng } : null;
  const near = origin ?? here ?? getLastSearchCoords();

  // The point and area to search for what's in the Where box, or null if it can't be found.
  // Unchanged text keeps the current area; a new place opens on that place (a town on the whole
  // town, an address on about the nearest 50 places).
  async function resolveWhere(): Promise<Pick<ResultsQuery, "where" | "lat" | "lng" | "b"> | null> {
    const text = where.trim();
    const unchanged = text === "" || text === current.where || text === CURRENT_LOCATION_LABEL || text === MAP_AREA_LABEL;
    if (unchanged && here && current.b) {
      return { where: current.where || text, lat: here.lat, lng: here.lng, b: current.b };
    }
    if (text === "" || text === MAP_AREA_LABEL) return { where: "", lat: null, lng: null, b: null };
    const found = await geocodeLocationText(text);
    if (!found) {
      setError("We couldn't find that place. Try a city, town or ZIP code.");
      return null;
    }
    addSearchHistory(text);
    const b = await startArea(supabase, found, { radiusMiles: found.radiusMiles, minPlaces: found.minPlaces });
    return { where: text, lat: found.lat, lng: found.lng, b };
  }

  async function search(patch: Partial<ResultsQuery>) {
    setError(null);
    const point = await resolveWhere();
    if (!point) return;
    go(resultsHref({ ...current, ...point, ...patch }));
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
  const whatId = layout === "bar" ? "what-bar" : "what-stacked";
  const whereId = layout === "bar" ? "where-bar" : "where-stacked";

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
      {/* Enter in either box searches; this button is for anyone who looks for one. */}
      <button type="submit" className="sr-only">
        Search
      </button>
      {(error || geo.geoError) && (
        <p role="alert" className={`text-sm text-red-700 ${layout === "bar" ? "absolute left-0 top-full mt-1 rounded bg-white px-2 py-1 shadow" : ""}`}>
          {error || geo.geoError}
        </p>
      )}
    </form>
  );
}
