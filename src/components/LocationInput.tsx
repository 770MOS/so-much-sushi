"use client";

import { useRef, useState, type FocusEvent } from "react";
import { CrosshairIcon, LocationPinIcon, HistoryIcon } from "@/components/icons";
import { getSearchHistory } from "@/lib/searchHistory";

type Props = {
  id?: string;
  value: string;
  onChange: (value: string) => void;
  onUseMyLocation: () => void;
  locating: boolean;
};

export default function LocationInput({ id, value, onChange, onUseMyLocation, locating }: Props) {
  const [focused, setFocused] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const showDropdown = focused && value.trim() === "";
  const history = getSearchHistory();

  function handleContainerBlur(e: FocusEvent<HTMLDivElement>) {
    if (!containerRef.current?.contains(e.relatedTarget as Node | null)) {
      setFocused(false);
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

  return (
    <div ref={containerRef} onBlur={handleContainerBlur} className="flex gap-2">
      <div className="relative w-full">
        <input
          id={id}
          type="text"
          placeholder="ZIP code or address"
          value={value}
          autoComplete="off"
          onFocus={() => setFocused(true)}
          onChange={(e) => onChange(e.target.value)}
          className="w-full rounded-none border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
        />
        {showDropdown && (
          <div className="absolute left-0 right-0 top-full z-10 mt-1 rounded-lg border border-zinc-300 bg-white py-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
            <button
              type="button"
              onClick={selectCurrentLocation}
              className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
            >
              <LocationPinIcon />
              Current Location
            </button>
            {history.length > 0 && (
              <>
                <p className="px-3 pt-2 pb-1 text-xs font-medium uppercase tracking-wide text-zinc-400 dark:text-zinc-500">
                  Search History
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
      <button
        type="button"
        onClick={onUseMyLocation}
        disabled={locating}
        aria-label={locating ? "Locating…" : "Use my location"}
        className="flex shrink-0 items-center justify-center rounded-lg border border-zinc-300 p-2.5 text-zinc-600 transition-colors hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:border-zinc-700 dark:text-zinc-400 dark:hover:text-zinc-100"
      >
        <CrosshairIcon />
      </button>
    </div>
  );
}
