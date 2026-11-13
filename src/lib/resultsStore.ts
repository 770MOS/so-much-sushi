"use client";

import { useSyncExternalStore } from "react";
import type { Coords } from "@/lib/lastSearchCoords";
import type { Facets } from "@/lib/searchTypes";
import type { ResultsQuery } from "@/lib/resultsQuery";

// What the results page has worked out, shared with the header's search boxes: the point it
// searched around (so suggestions start nearby) and the filter counts (so a suggested kind
// can say "12 nearby" without counting the area again), and its search while it's showing,
// so the boxes keep showing it while a place panel is open over the page. In memory only.
type ResultsState = { origin: Coords | null; facets: Facets | null; query: ResultsQuery | null };

const EMPTY: ResultsState = { origin: null, facets: null, query: null };
let state: ResultsState = EMPTY;
const listeners = new Set<() => void>();

export function setResultsState(patch: Partial<ResultsState>) {
  state = { ...state, ...patch };
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useResultsState(): ResultsState {
  return useSyncExternalStore(
    subscribe,
    () => state,
    () => EMPTY
  );
}
