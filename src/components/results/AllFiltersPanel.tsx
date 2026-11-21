"use client";

import { useEffect, useMemo, useState } from "react";
import { HEART_PATH, THUMB_PATH } from "@/components/icons";
import { typeForPath } from "@/lib/entityTypes";
import {
  cuisinesOf,
  DRAWN_AREA_LABEL,
  MAP_AREA_LABEL,
  moreCount,
  NO_MORE,
  resultsHref,
  withCuisines,
  type Chain,
  type Only,
  type ResultsQuery,
} from "@/lib/resultsQuery";
import type { Facets } from "@/lib/searchTypes";

// All filters (advanced search, mocked 2026-11-19, Design canvas row 8): opened from the
// Filters button on a computer, in place of the list; the map stays. Every choice applies at
// once (the address changes, the list and map follow), and every count is for the map area with
// the other filters on (public.area_facets with counts). "Show N places" closes the panel.
// Draw an area closes it and starts drawing on the map (step 3).

const FLAG_PATH = "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7";
const LOCK_PATH =
  "M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2zM11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0M8 11v-4a4 4 0 1 1 8 0v4";
const SHOWN_CUISINES = 14;

const SHOW_ONLY: { key: Only; label: string; d: string; color: string }[] = [
  { key: "favorites", label: "Your favorites", d: HEART_PATH, color: "var(--favorite-ink)" },
  { key: "friends", label: "Friends’ favorites", d: THUMB_PATH, color: "var(--friends-ink)" },
  { key: "want", label: "Want to try", d: FLAG_PATH, color: "var(--want)" },
];

function Icon({ d, color = "currentColor", size = 18 }: { d: string; color?: string; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

const chip = "inline-flex h-[38px] shrink-0 items-center gap-1.5 rounded-full px-3 text-sm font-medium";
const chipOff = `${chip} border border-[#dddddd] bg-white text-zinc-950 hover:border-zinc-400`;
const chipOn = `${chip} border-[1.5px] border-link bg-[#eef2fb] text-link`;
const section = "border-b border-[#f0f0f0] py-[18px]";
const legend = "float-left w-full pb-3 text-base font-medium text-zinc-950";
const field =
  "h-11 w-full rounded-[10px] border border-[#dddddd] bg-white px-3 text-[15px] text-zinc-950 placeholder:text-zinc-500 focus:border-zinc-500 focus:outline-none";

function n(v: number | undefined): string {
  return v === undefined ? "" : v.toLocaleString("en-US");
}

function Check() {
  return <Icon d="M5 12l5 5l10 -10" size={15} />;
}

export type ListOption = { id: string; name: string };

type Props = {
  query: ResultsQuery;
  facets: Facets | null;
  signedIn: boolean;
  lists: ListOption[];
  total: number | null;
  // area_facets with counts for a query (the same map area).
  countFor: (q: ResultsQuery) => Promise<Facets | null>;
  onChange: (patch: Partial<ResultsQuery>) => void;
  onLocked: () => void;
  onClose: () => void;
  onDraw: () => void;
};

const AREA_ICON =
  "M12 5m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M19 8m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M5 11m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M15 19m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M6.5 9.5l3.5 -3M14 5.5l3 1.5M18.5 10l-2.5 7M13.5 17.5l-7 -5";

export default function AllFiltersPanel({ query, facets, signedIn, lists, total, countFor, onChange, onLocked, onClose, onDraw }: Props) {
  const key = resultsHref(query);
  const [counted, setCounted] = useState<{ key: string; facets: Facets | null } | null>(null);
  const [allCuisines, setAllCuisines] = useState(false);
  const [name, setName] = useState(query.q);
  const [street, setStreet] = useState("");
  const [nameFor, setNameFor] = useState(query.q);
  // A new name from elsewhere (the What box) replaces what's typed here.
  if (nameFor !== query.q) {
    setNameFor(query.q);
    setName(query.q);
  }

  useEffect(() => {
    let cancelled = false;
    const t = setTimeout(() => {
      countFor(query).then((f) => {
        if (!cancelled) setCounted({ key, facets: f });
      });
    }, 150);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
    // query is captured through key.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  // The panel's counts for this search; the page's own (without the panel's extra counts) while
  // they're on their way.
  const c: Facets | null = counted?.key === key ? counted.facets : null;
  const shown = c ?? facets;
  const type = typeForPath(query.kind);
  const picked = cuisinesOf(query);
  const m = query.more;

  const forType = useMemo(
    () => (shown?.cuisines ?? []).filter((x) => (type ? typeForPath(x.path) === type : true)),
    [shown, type]
  );
  const cuisines = useMemo(() => {
    const list = allCuisines
      ? [...forType]
      : forType
          .filter((x) => x.path.split(".").length === 2)
          .sort((a, b) => b.n - a.n)
          .slice(0, SHOWN_CUISINES);
    for (const p of picked) {
      if (!list.some((x) => x.path === p)) {
        const found = forType.find((x) => x.path === p);
        list.push(found ?? { path: p, name: p.split(".").pop()!.replace(/_/g, " "), n: 0 });
      }
    }
    return list.sort((a, b) => a.name.localeCompare(b.name));
  }, [forType, allCuisines, picked]);

  function toggleCuisine(path: string) {
    const next = picked.includes(path) ? picked.filter((p) => p !== path) : [...picked, path];
    onChange(withCuisines(query, next, type));
  }

  function setMore(patch: Partial<ResultsQuery["more"]>) {
    onChange({ more: { ...m, ...patch } });
  }

  function toggleOnly(k: Only) {
    if (!signedIn) {
      onLocked();
      return;
    }
    onChange({ only: query.only.includes(k) ? query.only.filter((o) => o !== k) : [...query.only, k] });
  }

  const streets = c?.streets ?? [];
  const streetOn = m.street.trim();
  const streetChips = streetOn && !streets.some((s) => s.label.toLowerCase() === streetOn.toLowerCase())
    ? [{ street: streetOn.toLowerCase(), label: streetOn, n: undefined as number | undefined }, ...streets]
    : streets;
  const chainCounts = c?.chain;
  const anyChain = chainCounts ? chainCounts.chain + chainCounts.independent : undefined;
  const showTotal = c?.total ?? total;
  const hiddenOn = signedIn && query.hidden;
  const active = moreCount(query) + query.only.length + (picked.length ? 1 : 0) + (hiddenOn ? 1 : 0);

  const segment = (on: boolean) =>
    `h-10 flex-1 rounded-[9px] text-sm font-medium ${on ? "bg-primary text-white" : "text-muted hover:text-zinc-950"}`;

  return (
    <section id="all-filters" aria-labelledby="all-filters-h" className="flex h-full flex-col bg-white">
      <div className="flex shrink-0 items-center justify-between border-b border-line py-2.5 pl-6 pr-3">
        <h2 id="all-filters-h" className="text-xl font-medium text-zinc-950">
          All filters
        </h2>
        <button type="button" onClick={onClose} aria-label="Close filters" className="flex h-11 w-11 items-center justify-center rounded-lg text-zinc-950 hover:bg-zinc-100">
          <Icon d="M18 6l-12 12M6 6l12 12" size={22} />
        </button>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-6">
        <div className={`${section} flex flex-col gap-2.5`}>
          <label htmlFor="af-name" className="text-base font-medium text-zinc-950">
            Name
          </label>
          <input
            id="af-name"
            type="text"
            value={name}
            placeholder="Any part of the name"
            autoComplete="off"
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") onChange({ q: name.trim() });
            }}
            onBlur={() => {
              if (name.trim() !== query.q.trim()) onChange({ q: name.trim() });
            }}
            className={field}
          />
          <label className="flex min-h-10 cursor-pointer items-center gap-3 text-[15px] text-zinc-950">
            <input type="checkbox" role="switch" checked={m.close} onChange={() => setMore({ close: !m.close })} className="peer sr-only" />
            <span aria-hidden="true" className={`relative h-6 w-10 shrink-0 rounded-full transition-colors peer-focus-visible:ring-2 peer-focus-visible:ring-zinc-400 ${m.close ? "bg-primary" : "bg-[#d6d6d6]"}`}>
              <span className={`absolute top-[3px] h-[18px] w-[18px] rounded-full bg-white transition-all ${m.close ? "left-[19px]" : "left-[3px]"}`} />
            </span>
            <span>
              Close spellings too <span className="text-muted">· “sawasdee” finds Sawatdee Thai</span>
            </span>
          </label>
        </div>

        {forType.length > 0 && (
          <fieldset className={section}>
            <legend className={legend}>
              Cuisine <span className="text-sm font-normal text-muted">· pick any number</span>
            </legend>
            <div className="clear-both flex flex-wrap gap-2">
              {cuisines.map((x) => {
                const on = picked.includes(x.path);
                return (
                  <button key={x.path} type="button" aria-pressed={on} onClick={() => toggleCuisine(x.path)} className={on ? chipOn : chipOff}>
                    {on && <Check />}
                    {x.name}
                    <span className={on ? "opacity-80" : "text-zinc-500"}>{n(x.n)}</span>
                  </button>
                );
              })}
            </div>
            {(allCuisines || forType.length > cuisines.length) && (
              <button type="button" onClick={() => setAllCuisines((a) => !a)} className="mt-2 h-10 text-sm font-medium text-zinc-950 underline">
                {allCuisines ? "Fewer cuisines" : `All ${forType.length} cuisines`}
              </button>
            )}
          </fieldset>
        )}

        <fieldset className={section}>
          <legend className={legend}>Street</legend>
          <div className="clear-both flex flex-wrap gap-2">
            {streetChips.map((s) => {
              const on = streetOn.toLowerCase() === s.label.toLowerCase();
              return (
                <button key={s.street} type="button" aria-pressed={on} onClick={() => setMore({ street: on ? "" : s.label })} className={on ? chipOn : chipOff}>
                  {on && <Check />}
                  {s.label}
                  {s.n !== undefined && <span className={on ? "opacity-80" : "text-zinc-500"}>{n(s.n)}</span>}
                </button>
              );
            })}
            {streetChips.length === 0 && c && <p className="text-sm text-muted">No street names for these places.</p>}
          </div>
          <label htmlFor="af-street" className="sr-only">
            Another street
          </label>
          <input
            id="af-street"
            type="text"
            value={street}
            placeholder="Another street"
            autoComplete="off"
            onChange={(e) => setStreet(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && street.trim()) {
                setMore({ street: street.trim() });
                setStreet("");
              }
            }}
            className={`${field} mt-2.5`}
          />
        </fieldset>

        <fieldset className={section}>
          <legend className={legend}>Chain or independent</legend>
          <div role="radiogroup" aria-label="Chain or independent" className="clear-both flex gap-0.5 rounded-xl border border-[#dddddd] p-[3px]">
            {(
              [
                [null, "Any", anyChain],
                ["independent", "Independent", chainCounts?.independent],
                ["chain", "Chains", chainCounts?.chain],
              ] as [Chain | null, string, number | undefined][]
            ).map(([value, label, count]) => {
              const on = m.chain === value;
              return (
                <button key={label} type="button" role="radio" aria-checked={on} onClick={() => setMore({ chain: value })} className={segment(on)}>
                  {label} <span className={on ? "opacity-75" : "text-zinc-500"}>{n(count)}</span>
                </button>
              );
            })}
          </div>
          <p className="mt-2.5 text-[13px] leading-snug text-muted">A chain is a name with 10 or more places nationwide.</p>
        </fieldset>

        <fieldset className={`${section} pb-2.5`}>
          <legend className={`${legend} pb-1`}>Details</legend>
          <div className="clear-both">
            {(
              [
                ["website", "Has a website", c?.website],
                ["phone", "Has a phone number", c?.phone],
                ["closed", "Include places that have closed", c?.closed],
              ] as ["website" | "phone" | "closed", string, number | undefined][]
            ).map(([k, label, count]) => (
              <label key={k} className="flex min-h-[46px] cursor-pointer items-center gap-3 text-[15px] text-zinc-950">
                <input type="checkbox" checked={m[k]} onChange={() => setMore({ [k]: !m[k] } as Partial<ResultsQuery["more"]>)} className="h-[22px] w-[22px] shrink-0 accent-zinc-950" />
                <span className="flex-1">{label}</span>
                <span className="text-sm text-muted">{count === undefined ? "" : k === "closed" ? `+${n(count)}` : n(count)}</span>
              </label>
            ))}
            {signedIn && (
              <label className="flex min-h-[46px] cursor-pointer items-center gap-3 text-[15px] text-zinc-950">
                <input type="checkbox" checked={query.hidden} onChange={() => onChange({ hidden: !query.hidden })} className="h-[22px] w-[22px] shrink-0 accent-zinc-950" />
                <span className="flex-1">Include places you hid</span>
                {/* Counted only while they're left out. */}
                <span className="text-sm text-muted">{query.hidden || !shown ? "" : `+${n(shown.hidden)}`}</span>
              </label>
            )}
          </div>
        </fieldset>

        <fieldset className={`${section} pb-2.5`}>
          <legend className={`${legend} pb-1`}>Show only</legend>
          <div className="clear-both">
            {SHOW_ONLY.map((s) => {
              const on = signedIn && query.only.includes(s.key);
              const count = signedIn ? shown?.[s.key] : undefined;
              return (
                <label key={s.key} className="flex min-h-[46px] cursor-pointer items-center gap-3 text-[15px] text-zinc-950">
                  <input type="checkbox" checked={on} onChange={() => toggleOnly(s.key)} className="h-[22px] w-[22px] shrink-0 accent-zinc-950" />
                  <Icon d={s.d} color={s.color} size={19} />
                  <span className="flex-1">{s.label}</span>
                  {signedIn ? (
                    <span className="text-sm text-muted">{n(count)}</span>
                  ) : (
                    <span className="flex items-center gap-1 text-[13px] text-muted">
                      <Icon d={LOCK_PATH} color="#707070" size={14} />
                      Join free
                    </span>
                  )}
                </label>
              );
            })}
            {signedIn && lists.length > 0 && (
              <div className="flex min-h-[46px] items-center gap-3">
                <label htmlFor="af-list" className="flex-1 text-[15px] text-zinc-950">
                  On one of your lists
                </label>
                <select
                  id="af-list"
                  value={m.list ?? ""}
                  onChange={(e) => setMore({ list: e.target.value || null })}
                  className="h-10 max-w-[200px] rounded-[10px] border border-[#dddddd] bg-white px-2.5 text-sm text-zinc-950"
                >
                  <option value="">Any list</option>
                  {lists.map((l) => (
                    <option key={l.id} value={l.id}>
                      {l.name}
                    </option>
                  ))}
                </select>
              </div>
            )}
          </div>
        </fieldset>

        <fieldset className={section}>
          <legend className={legend}>Search area</legend>
          <div className="clear-both flex flex-wrap items-center gap-2.5">
            <span className="inline-flex h-10 items-center rounded-[10px] bg-[#f5f5f5] px-3.5 text-sm text-zinc-950">
              {m.area ? "Your drawn area" : "The map area"}
            </span>
            <button type="button" onClick={onDraw} className="inline-flex h-10 items-center gap-2 rounded-[10px] border border-[#dddddd] px-3.5 text-sm font-medium text-zinc-950 hover:border-zinc-400">
              <Icon d={AREA_ICON} />
              {m.area ? "Draw again" : "Draw an area"}
            </button>
            {m.area && (
              <button
                type="button"
                onClick={() => onChange({ more: { ...m, area: null }, where: query.where === DRAWN_AREA_LABEL ? MAP_AREA_LABEL : query.where })}
                className="h-10 px-1.5 text-sm font-medium text-zinc-950 underline"
              >
                Remove it
              </button>
            )}
          </div>
        </fieldset>

        <p className="py-4 pb-5 text-[13px] leading-normal text-zinc-500">
          Hours, price and things like outdoor seating come once we have that information for places.
        </p>
      </div>

      <div className="flex shrink-0 items-center justify-between gap-3 border-t border-line bg-white px-6 py-3">
        <button
          type="button"
          disabled={active === 0}
          onClick={() =>
            onChange({ ...withCuisines(query, [], type), only: [], more: NO_MORE, hidden: false, where: query.where === DRAWN_AREA_LABEL ? MAP_AREA_LABEL : query.where })
          }
          className="h-11 px-1 text-[15px] font-medium text-zinc-950 underline disabled:text-zinc-400 disabled:no-underline"
        >
          Clear all
        </button>
        <button type="button" onClick={onClose} className="h-12 rounded-xl bg-primary px-6 text-base font-medium text-white hover:bg-primary-hover">
          {showTotal === null || showTotal === undefined
            ? "Show places"
            : showTotal === 0
              ? "No places match"
              : `Show ${showTotal.toLocaleString("en-US")} ${showTotal === 1 ? "place" : "places"}`}
        </button>
      </div>
    </section>
  );
}
