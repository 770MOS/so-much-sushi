"use client";

import { useEffect, useId, useMemo, useRef, useState, type FocusEvent, type KeyboardEvent } from "react";
import { CrosshairIcon, LocationPinIcon, HistoryIcon } from "@/components/icons";
import { getSearchHistory } from "@/lib/searchHistory";
import { createClient } from "@/lib/supabase/client";
import { CURRENT_LOCATION_LABEL, getLastSearchCoords, type Coords } from "@/lib/lastSearchCoords";
import { rememberPickedLocation, type PickedLocation } from "@/lib/locationLookup";

type Props = {
  id?: string;
  value: string;
  onChange: (value: string) => void;
  onUseMyLocation: () => void;
  locating: boolean;
  // Where the person's map is, so nearby places are suggested first. Defaults to this
  // session's last search position.
  near?: Coords | null;
  // For a box drawn inside another frame (the header's search bar): replaces the input's own
  // border and padding, and leaves out the separate "Use my location" button.
  inputClassName?: string;
  hideLocateButton?: boolean;
  placeholder?: string;
};

type Suggestion = PickedLocation & { kind: "place" | "zip"; detail: string | null };

// Suggestions start after two characters, a short pause after the last keystroke.
const MIN_CHARS = 2;
const DEBOUNCE_MS = 150;
const MAX_SUGGESTIONS = 8;

export default function LocationInput({
  id,
  value,
  onChange,
  onUseMyLocation,
  locating,
  near,
  inputClassName,
  hideLocateButton,
  placeholder = "City, town or ZIP code",
}: Props) {
  const supabase = useMemo(() => createClient(), []);
  const listId = useId();
  const [focused, setFocused] = useState(false);
  // The latest answer; it stays on screen while the next keystroke's answer loads.
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [active, setActive] = useState(-1);
  // The label of a suggestion just picked: no dropdown for it until the text changes.
  const [pickedLabel, setPickedLabel] = useState<string | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const requestRef = useRef(0);

  const query = value.trim();
  const wantsSuggestions =
    focused && query.length >= MIN_CHARS && value !== CURRENT_LOCATION_LABEL && value !== pickedLabel;

  const nearLat = near?.lat;
  const nearLng = near?.lng;

  useEffect(() => {
    if (!wantsSuggestions) return;
    const requestId = ++requestRef.current;
    const timer = setTimeout(async () => {
      const point = nearLat !== undefined && nearLng !== undefined ? { lat: nearLat, lng: nearLng } : getLastSearchCoords();
      const { data, error } = await supabase.rpc("suggest_localities", {
        query,
        near_lat: point?.lat ?? null,
        near_lng: point?.lng ?? null,
        max_results: MAX_SUGGESTIONS,
      });
      // A newer keystroke has started its own request; drop this answer.
      if (requestId !== requestRef.current) return;
      setSuggestions(error || !data ? [] : (data as Suggestion[]));
      setActive(-1);
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [wantsSuggestions, query, nearLat, nearLng, supabase]);

  const visibleSuggestions = wantsSuggestions ? suggestions : [];
  const showStartList = focused && query === "";
  const showSuggestions = visibleSuggestions.length > 0;
  const history = showStartList ? getSearchHistory() : [];

  function handleContainerBlur(e: FocusEvent<HTMLDivElement>) {
    if (!containerRef.current?.contains(e.relatedTarget as Node | null)) {
      setFocused(false);
      setActive(-1);
    }
  }

  function selectCurrentLocation() {
    setFocused(false);
    onUseMyLocation();
  }

  function selectHistoryItem(item: string) {
    setFocused(false);
    onChange(item);
  }

  function pick(suggestion: Suggestion) {
    rememberPickedLocation({
      label: suggestion.label,
      lat: suggestion.lat,
      lng: suggestion.lng,
      city: suggestion.city,
      state: suggestion.state,
    });
    setPickedLabel(suggestion.label);
    setActive(-1);
    onChange(suggestion.label);
  }

  function handleKeyDown(e: KeyboardEvent<HTMLInputElement>) {
    if (!showSuggestions) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((i) => (i + 1) % visibleSuggestions.length);
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => (i <= 0 ? visibleSuggestions.length - 1 : i - 1));
    } else if (e.key === "Enter" && active >= 0) {
      // Enter on a highlighted suggestion picks it; Enter with none highlighted submits
      // the form with the typed text, looked up as before.
      e.preventDefault();
      pick(visibleSuggestions[active]);
    } else if (e.key === "Escape") {
      e.preventDefault();
      setPickedLabel(value);
    }
  }

  const optionId = (i: number) => `${listId}-option-${i}`;

  return (
    <div ref={containerRef} onBlur={handleContainerBlur} className="flex min-w-0 flex-1 gap-2">
      <div className="relative w-full">
        {/* type="search" with no address-like id or wording: Safari otherwise takes this
            for an address form and offers to fill in the person's contact card. */}
        <input
          id={id}
          type="search"
          role="combobox"
          aria-expanded={showSuggestions}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={active >= 0 ? optionId(active) : undefined}
          placeholder={placeholder}
          value={value}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
          spellCheck={false}
          enterKeyHint="search"
          onFocus={() => setFocused(true)}
          onChange={(e) => {
            setPickedLabel(null);
            onChange(e.target.value);
          }}
          onKeyDown={handleKeyDown}
          className={
            inputClassName ??
            "w-full rounded-none border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
          }
        />
        {showSuggestions && (
          <ul
            id={listId}
            role="listbox"
            // Keep focus in the box while clicking: Safari doesn't focus a clicked button, so
            // the box's blur would otherwise close the list before the click lands.
            onMouseDown={(e) => e.preventDefault()}
            className="absolute left-0 right-0 top-full z-10 mt-1 max-h-80 overflow-y-auto rounded-lg border border-zinc-300 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900"
          >
            {visibleSuggestions.map((s, i) => (
              <li key={`${s.kind}-${s.label}-${i}`} id={optionId(i)} role="option" aria-selected={i === active}>
                <button
                  type="button"
                  tabIndex={-1}
                  onMouseEnter={() => setActive(i)}
                  onClick={() => pick(s)}
                  className={`flex w-full items-baseline gap-2 px-3 py-2 text-left text-sm text-zinc-950 dark:text-zinc-50 ${
                    i === active ? "bg-zinc-100 dark:bg-zinc-800" : ""
                  }`}
                >
                  <span>{s.label}</span>
                  {s.detail && <span className="text-xs text-zinc-500 dark:text-zinc-400">{s.detail}</span>}
                </button>
              </li>
            ))}
          </ul>
        )}
        {showStartList && (
          <div
            onMouseDown={(e) => e.preventDefault()}
            className="absolute left-0 right-0 top-full z-10 mt-1 rounded-lg border border-zinc-300 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900"
          >
            <button
              type="button"
              onClick={selectCurrentLocation}
              className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
            >
              <LocationPinIcon />
              Use my location
            </button>
            {history.length > 0 && (
              <>
                <p className="px-3 pt-2 pb-1 text-xs font-medium text-zinc-500 dark:text-zinc-500">
                  Recent places, kept on this device
                </p>
                {history.map((item) => (
                  <button
                    key={item}
                    type="button"
                    onClick={() => selectHistoryItem(item)}
                    className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
                  >
                    <HistoryIcon />
                    {item}
                  </button>
                ))}
              </>
            )}
          </div>
        )}
      </div>
      {!hideLocateButton && (
      <button
        type="button"
        onClick={onUseMyLocation}
        disabled={locating}
        aria-label={locating ? "Locating…" : "Use my location"}
        className="flex shrink-0 items-center justify-center rounded-lg border border-zinc-300 p-2.5 text-zinc-600 transition-colors hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
      >
        <CrosshairIcon />
      </button>
      )}
    </div>
  );
}
