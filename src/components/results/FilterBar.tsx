"use client";

import { useEffect, useRef, useState } from "react";
import { HEART_PATH, THUMB_PATH } from "@/components/icons";
import { TYPE_OPTIONS, typeForPath } from "@/lib/entityTypes";
import type { Only, ResultsQuery, View } from "@/lib/resultsQuery";
import type { Facets } from "@/lib/searchTypes";

const FLAG_PATH = "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7";
const LOCK_PATH =
  "M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2zM11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0M8 11v-4a4 4 0 1 1 8 0v4";

function Icon({ d, color, size = 17, fill = "none" }: { d: string; color: string; size?: number; fill?: string }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill={fill} stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

function Count({ n, on }: { n: number | undefined; on: boolean }) {
  if (n === undefined) return null;
  return <span className={on ? "opacity-80" : "text-zinc-500"}>{n.toLocaleString("en-US")}</span>;
}

const chipBase =
  "inline-flex h-10 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-sm font-medium transition-colors";
const chipOff = `${chipBase} border border-[#dddddd] bg-white text-zinc-950 hover:border-zinc-400`;
const chipOn = `${chipBase} border border-primary bg-primary text-white`;

const STATUS: { key: Only; label: string; short: string; d: string; color: string; onClass: string }[] = [
  { key: "favorites", label: "Favorites", short: "Favs", d: HEART_PATH, color: "var(--favorite-ink)", onClass: "border-[1.5px] border-favorite-ink bg-[#fdf0f4] text-favorite-ink" },
  { key: "friends", label: "Friends", short: "Friends", d: THUMB_PATH, color: "var(--friends-ink)", onClass: "border-[1.5px] border-friends-ink bg-[#ecf6f0] text-friends-ink" },
  { key: "want", label: "Want to try", short: "Want to try", d: FLAG_PATH, color: "var(--want)", onClass: "border-[1.5px] border-want bg-[#eef1fc] text-want" },
];

type Props = {
  query: ResultsQuery;
  facets: Facets | null;
  signedIn: boolean;
  kindName: (path: string) => string;
  onChange: (patch: Partial<ResultsQuery>) => void;
  onLocked: () => void;
  // Phone: opens the filters sheet.
  onOpenFilters?: () => void;
};

function CuisineMenu({ query, facets, kindName, onChange }: Pick<Props, "query" | "facets" | "kindName" | "onChange">) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const type = typeForPath(query.kind);
  const cuisine = query.kind && query.kind.includes(".") ? query.kind : null;
  const options = (facets?.cuisines ?? []).filter((c) => typeForPath(c.path) === type);

  useEffect(() => {
    if (!open) return;
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  if (!type || (!cuisine && options.length === 0)) return null;

  return (
    <div ref={ref} className="relative shrink-0">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className={
          cuisine
            ? `${chipBase} border-[1.5px] border-link bg-[#eef2fb] pl-3.5 pr-3 text-link`
            : `${chipOff} pr-3`
        }
      >
        {cuisine ? kindName(cuisine) : "Cuisine"}
        <Icon d="M6 9l6 6l6 -6" color="currentColor" size={16} />
      </button>
      {open && (
        <ul
          role="listbox"
          aria-label="Cuisine"
          className="absolute left-0 top-full z-30 mt-2 max-h-80 w-64 overflow-y-auto rounded-xl border border-line bg-white py-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]"
        >
          <li role="option" aria-selected={!cuisine}>
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                onChange({ kind: type });
              }}
              className={`flex min-h-11 w-full items-center px-3 text-left text-[15px] hover:bg-zinc-50 ${!cuisine ? "font-medium" : ""}`}
            >
              Any cuisine
            </button>
          </li>
          {options.map((c) => {
            const depth = c.path.split(".").length;
            return (
              <li key={c.path} role="option" aria-selected={cuisine === c.path}>
                <button
                  type="button"
                  onClick={() => {
                    setOpen(false);
                    onChange({ kind: c.path });
                  }}
                  className={`flex min-h-11 w-full items-center justify-between gap-3 px-3 text-left text-[15px] hover:bg-zinc-50 ${
                    cuisine === c.path ? "font-medium text-link" : "text-zinc-950"
                  }`}
                  style={{ paddingLeft: depth > 2 ? 28 : 12 }}
                >
                  <span>{c.name}</span>
                  <span className="text-[13px] font-normal text-zinc-500">{c.n.toLocaleString("en-US")}</span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

// The row of filters above the results: type, cuisine, your places, then sort, distance and
// view. Counts come from public.area_facets for the same area and name.
export default function FilterBar({ query, facets, signedIn, kindName, onChange, onLocked, onOpenFilters }: Props) {
  const type = typeForPath(query.kind);
  const cuisine = query.kind && query.kind.includes(".") ? query.kind : null;
  // A cuisine counts once: it is a type too.
  const active = (query.kind ? 1 : 0) + (signedIn ? query.only.length : 0);

  function toggleOnly(key: Only) {
    if (!signedIn) {
      onLocked();
      return;
    }
    const only = query.only.includes(key) ? query.only.filter((o) => o !== key) : [...query.only, key];
    onChange({ only });
  }

  return (
    <div className="flex flex-col gap-2 border-b border-line px-4 py-2.5 md:flex-row md:flex-wrap md:items-center md:gap-2 md:px-6">
      {/* On a phone the chips scroll sideways in one line; on a computer they wrap, with the
          view switch at the end of the last line. */}
      <div className="-mx-4 flex items-center gap-2 overflow-x-auto px-4 pb-0.5 md:contents">
        {onOpenFilters && (
          <button type="button" onClick={onOpenFilters} className={`${active ? chipOn : chipOff} md:hidden`} aria-label={active ? `Filters, ${active} on` : "Filters"}>
            <Icon d="M4 6h8M16 6h4M4 12h2M10 12h10M4 18h11M19 18h1M14 4v4M8 10v4M17 16v4" color="currentColor" size={17} />
            Filters
            {active > 0 && (
              <span className="flex h-5 min-w-5 items-center justify-center rounded-full bg-white px-1 text-xs font-medium text-zinc-950">{active}</span>
            )}
          </button>
        )}
        <div role="group" aria-label="Type of place" className="flex gap-2">
          {TYPE_OPTIONS.map((t) => {
            const on = t.key === "all" ? !type : type === t.key;
            return (
              <button
                key={t.key}
                type="button"
                aria-pressed={on}
                onClick={() => onChange({ kind: t.key === "all" ? null : t.key })}
                className={on ? chipOn : chipOff}
              >
                {t.label}
                <Count n={facets?.types[t.key]} on={on} />
              </button>
            );
          })}
        </div>
        {/* On a phone the cuisine choice is in the filters sheet, where a list has room. */}
        <div className={onOpenFilters ? "hidden md:contents" : "contents"}>
          <CuisineMenu query={query} facets={facets} kindName={kindName} onChange={onChange} />
        </div>
        {onOpenFilters && type && (
          <button
            type="button"
            onClick={onOpenFilters}
            className={
              cuisine
                ? `${chipBase} border-[1.5px] border-link bg-[#eef2fb] pr-3 text-link md:hidden`
                : `${chipOff} pr-3 md:hidden`
            }
          >
            {cuisine ? kindName(cuisine) : "Cuisine"}
            <Icon d="M6 9l6 6l6 -6" color="currentColor" size={16} />
          </button>
        )}
        <span aria-hidden="true" className="mx-1 h-6 w-px shrink-0 bg-[#dddddd]" />
        <div role="group" aria-label="Your places" className="flex gap-2">
          {STATUS.map((s) => {
            const on = signedIn && query.only.includes(s.key);
            const n = signedIn ? facets?.[s.key] : undefined;
            return (
              <button
                key={s.key}
                type="button"
                aria-pressed={signedIn ? on : undefined}
                aria-label={signedIn ? undefined : `${s.label}: join free to use`}
                onClick={() => toggleOnly(s.key)}
                className={on ? `${chipBase} ${s.onClass}` : chipOff}
              >
                <Icon d={s.d} color={s.color} />
                <span className="md:hidden">{s.short}</span>
                <span className="hidden md:inline">{s.label}</span>
                {signedIn ? <Count n={n} on={false} /> : <Icon d={LOCK_PATH} color="#707070" size={14} />}
              </button>
            );
          })}
        </div>
      </div>

      <div className="hidden md:ml-auto md:flex">
        <div role="group" aria-label="View" className="flex gap-0.5 rounded-xl border border-[#dddddd] p-[3px]">
          {(["list", "split", "map"] as View[]).map((v) => (
            <button
              key={v}
              type="button"
              aria-pressed={query.view === v}
              onClick={() => onChange({ view: v })}
              className={`h-[34px] rounded-[9px] px-3 text-sm font-medium ${
                query.view === v ? "bg-primary text-white" : "text-muted hover:text-zinc-950"
              }`}
            >
              {v === "list" ? "List" : v === "split" ? "Split" : "Map"}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

// Sort, shown under the result count. (There is no distance menu: the map area is the search
// area, build step 3.)
export function SortMenu({ query, onChange }: Pick<Props, "query" | "onChange">) {
  const select = "h-9 appearance-none bg-transparent pl-0 pr-6 text-sm font-medium text-zinc-950 focus:outline-none";
  return (
    <div className="flex items-center gap-4">
      <label className="relative">
        <span className="sr-only">Sort</span>
        <select value={query.sort} onChange={(e) => onChange({ sort: e.target.value === "az" ? "az" : "nearest" })} className={select}>
          <option value="nearest">Nearest first</option>
          <option value="az">Name A–Z</option>
        </select>
        <span className="pointer-events-none absolute right-1 top-2.5">
          <Icon d="M6 9l6 6l6 -6" color="#141414" size={16} />
        </span>
      </label>
    </div>
  );
}
