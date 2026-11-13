"use client";

import { useEffect, useId, useMemo, useRef, useState, type FocusEvent, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { createClient } from "@/lib/supabase/client";
import type { Coords } from "@/lib/lastSearchCoords";
import type { Facets } from "@/lib/searchTypes";

type KindSuggestion = { kind: "kind"; label: string; path: string; type_key: string };
type PlaceSuggestion = { kind: "place"; label: string; place_id: string; address: string | null; miles: number | null };
type Suggestion = KindSuggestion | PlaceSuggestion;
type Option = Suggestion | { kind: "names"; label: string };

type Props = {
  id: string;
  value: string;
  onChange: (value: string) => void;
  // Picking a kind sets the type or cuisine filter; picking a place opens it.
  onPickKind: (path: string) => void;
  onPickPlace: (placeId: string) => void;
  // Enter, or "Search names with …": the text becomes a name search.
  onSubmitText: () => void;
  near: Coords | null;
  facets: Facets | null;
  className?: string;
  inputClassName?: string;
  autoFocus?: boolean;
  // The phone's search screen: the suggestions go in this element, as a full-width list
  // under the boxes, instead of a dropdown.
  listTarget?: HTMLElement | null;
};

const MIN_CHARS = 2;
const DEBOUNCE_MS = 150;

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M10 10m-7 0a7 7 0 1 0 14 0a7 7 0 1 0 -14 0M21 21l-6 -6" />
    </svg>
  );
}

// How many of a kind are in the area the page last searched, from its filter counts.
function nearbyCount(facets: Facets | null, path: string): number | null {
  if (!facets) return null;
  if (!path.includes(".")) return facets.types[path as keyof Facets["types"]] ?? null;
  return facets.cuisines.find((c) => c.path === path)?.n ?? null;
}

// The What box: a name, a cuisine or a kind of place. Suggestions come from our own list
// (public.suggest_what): kinds of places, then places by name, nearest first.
export default function WhatBox({
  id,
  value,
  onChange,
  onPickKind,
  onPickPlace,
  onSubmitText,
  near,
  facets,
  className,
  inputClassName,
  autoFocus,
  listTarget,
}: Props) {
  const supabase = useMemo(() => createClient(), []);
  const listId = useId();
  // A box that starts focused (the phone's search screen) never gets a focus event for it.
  const [focused, setFocused] = useState(Boolean(autoFocus));
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [active, setActive] = useState(-1);
  // Text the person has just acted on: no dropdown for it until they type again.
  const [settled, setSettled] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const requestRef = useRef(0);

  const query = value.trim();
  const wants = focused && query.length >= MIN_CHARS && value !== settled;
  const nearLat = near?.lat ?? null;
  const nearLng = near?.lng ?? null;

  useEffect(() => {
    if (!wants) return;
    const requestId = ++requestRef.current;
    const timer = setTimeout(async () => {
      const { data, error } = await supabase.rpc("suggest_what", { q: query, ref_lat: nearLat, ref_lng: nearLng });
      if (requestId !== requestRef.current) return;
      setSuggestions(error || !data ? [] : (data as Suggestion[]));
      setActive(-1);
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [wants, query, nearLat, nearLng, supabase]);

  const kinds = wants ? suggestions.filter((s): s is KindSuggestion => s.kind === "kind") : [];
  const places = wants ? suggestions.filter((s): s is PlaceSuggestion => s.kind === "place") : [];
  const options: Option[] = wants ? [...kinds, ...places, { kind: "names", label: query }] : [];
  const open = options.length > 0;

  function choose(option: Option) {
    setSettled(value);
    setActive(-1);
    setFocused(false);
    if (option.kind === "kind") onPickKind(option.path);
    else if (option.kind === "place") onPickPlace(option.place_id);
    else onSubmitText();
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter") {
      e.preventDefault();
      if (open && active >= 0) choose(options[active]);
      else {
        setSettled(value);
        setFocused(false);
        onSubmitText();
      }
      return;
    }
    if (!open) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((i) => (i + 1) % options.length);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => (i <= 0 ? options.length - 1 : i - 1));
    } else if (e.key === "Escape") {
      e.preventDefault();
      setSettled(value);
    }
  }

  function handleBlur(e: FocusEvent<HTMLDivElement>) {
    if (!containerRef.current?.contains(e.relatedTarget as Node | null)) {
      setFocused(false);
      setActive(-1);
    }
  }

  const optionId = (i: number) => `${listId}-option-${i}`;
  const inline = Boolean(listTarget);
  const rowClass = (i: number) =>
    `flex w-full items-center gap-3 text-left text-[15px] text-zinc-950 ${inline ? "min-h-14 px-4 py-2" : "min-h-12 px-3 py-1.5"} ${
      i === active ? "bg-[#f3f6fd]" : ""
    }`;
  const headingClass = inline ? "px-4 pb-1 pt-3 text-[13px] font-medium text-muted" : "px-3 pb-1 pt-2 text-[13px] font-medium text-muted";

  const list = (

    <div
      id={listId}
      role="listbox"
      aria-label="Suggestions"
      // Keep focus in the box while clicking (Safari doesn't focus clicked buttons).
      onMouseDown={(e) => e.preventDefault()}
      className={
        inline
          ? "bg-white py-1"
          : "absolute left-0 right-0 top-full z-40 mt-2 min-w-[300px] overflow-hidden rounded-xl border border-line bg-white py-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]"
      }
    >
      {kinds.length > 0 && <p className={headingClass}>Kinds of places</p>}
      {kinds.map((k, i) => {
        const n = nearbyCount(facets, k.path);
        return (
          <div key={k.path} id={optionId(i)} role="option" aria-selected={i === active}>
            <button type="button" tabIndex={-1} onMouseEnter={() => setActive(i)} onClick={() => choose(k)} className={rowClass(i)}>
              <span className="flex-1 font-medium text-link">{k.label}</span>
              {n !== null && <span className="text-[13px] text-muted">{n.toLocaleString("en-US")} nearby</span>}
            </button>
          </div>
        );
      })}
      {places.length > 0 && <p className={headingClass}>Places</p>}
      {places.map((p, j) => {
        const i = kinds.length + j;
        return (
          <div key={p.place_id} id={optionId(i)} role="option" aria-selected={i === active}>
            <button type="button" tabIndex={-1} onMouseEnter={() => setActive(i)} onClick={() => choose(p)} className={rowClass(i)}>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="truncate">{p.label}</span>
                {p.address && <span className="truncate text-[13px] text-muted">{p.address}</span>}
              </span>
              {p.miles !== null && <span className="shrink-0 text-[13px] text-muted">{Number(p.miles).toFixed(1)} mi</span>}
            </button>
          </div>
        );
      })}
      {(() => {
        const i = options.length - 1;
        return (
          <div id={optionId(i)} role="option" aria-selected={i === active} className="border-t border-line">
            <button type="button" tabIndex={-1} onMouseEnter={() => setActive(i)} onClick={() => choose(options[i])} className={rowClass(i)}>
              <span className="text-muted">
                <SearchIcon />
              </span>
              <span>
                Search names with “<span className="font-medium">{query}</span>”
              </span>
            </button>
          </div>
        );
      })()}
    </div>
  );

  return (
    <div ref={containerRef} onBlur={handleBlur} className={`relative min-w-0 flex-1 ${className ?? ""}`}>
      <input
        id={id}
        type="text"
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={active >= 0 ? optionId(active) : undefined}
        placeholder="Name, cuisine or kind of place"
        value={value}
        autoComplete="off"
        autoCorrect="off"
        spellCheck={false}
        enterKeyHint="search"
        autoFocus={autoFocus}
        onFocus={() => setFocused(true)}
        onChange={(e) => {
          setSettled(null);
          onChange(e.target.value);
        }}
        onKeyDown={handleKeyDown}
        className={inputClassName ?? "w-full bg-transparent text-[15px] text-zinc-950 placeholder:text-zinc-500 focus:outline-none"}
      />
      {open && (inline ? createPortal(list, listTarget!) : list)}
    </div>
  );
}
