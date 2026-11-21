"use client";

import { useEffect, useMemo, useState } from "react";
import { HEART_PATH, THUMB_PATH } from "@/components/icons";
import { TYPE_OPTIONS, typeForPath } from "@/lib/entityTypes";
import {
  cuisinesOf,
  moreCount,
  NO_MORE,
  resultsHref,
  withCuisines,
  type Chain,
  type MoreFilters,
  type Only,
  type ResultsQuery,
} from "@/lib/resultsQuery";
import type { Facets } from "@/lib/searchTypes";
import type { ListOption } from "@/components/results/AllFiltersPanel";

// The phone's filters sheet (mocked 2026-11-12; More filters added 2026-11-19): type, cuisine
// (any number; the most common nearby, shown A-Z with their counts, then "All N cuisines"), Show
// only (your favorites, friends' favorites, Want to try, one of your lists), and More filters
// (street, chain or independent, website, phone, closed places). Nothing changes until "Show N
// places", which counts the choices made here for the same area and name.

const FLAG_PATH = "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7";
const LOCK_PATH =
  "M5 13a2 2 0 0 1 2 -2h10a2 2 0 0 1 2 2v6a2 2 0 0 1 -2 2h-10a2 2 0 0 1 -2 -2zM11 16a1 1 0 1 0 2 0a1 1 0 0 0 -2 0M8 11v-4a4 4 0 1 1 8 0v4";
const SHOWN_CUISINES = 12;

const SHOW_ONLY: { key: Only; label: string; d: string; color: string }[] = [
  { key: "favorites", label: "Your favorites", d: HEART_PATH, color: "var(--favorite-ink)" },
  { key: "friends", label: "Friends’ favorites", d: THUMB_PATH, color: "var(--friends-ink)" },
  { key: "want", label: "Want to try", d: FLAG_PATH, color: "var(--want)" },
];

function Icon({ d, color, size = 20 }: { d: string; color: string; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

const chip = "inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-sm font-medium";
const chipOff = `${chip} border border-[#dddddd] bg-white text-zinc-950`;
const chipOn = `${chip} border border-primary bg-primary text-white`;
const chipKind = `${chip} border-[1.5px] border-link bg-[#eef2fb] text-link`;
const legend = "float-left w-full pb-2.5 pt-3 text-base font-medium text-zinc-950";

type Props = {
  query: ResultsQuery;
  facets: Facets | null;
  signedIn: boolean;
  lists: ListOption[];
  // The counts for a search in the same area (with the panel's own counts).
  countFor: (q: ResultsQuery) => Promise<Facets | null>;
  onApply: (patch: Partial<ResultsQuery>) => void;
  onLocked: () => void;
  onClose: () => void;
  // Draw an area: the choices made here apply, then drawing starts on the map.
  onDraw: (patch: Partial<ResultsQuery>) => void;
};

export default function FiltersSheet({ query, facets, signedIn, lists, countFor, onApply, onLocked, onClose, onDraw }: Props) {
  const [kind, setKind] = useState<string | null>(query.kind);
  const [more, setMore] = useState<MoreFilters>(query.more);
  const [only, setOnly] = useState<Only[]>(query.only);
  const [hidden, setHidden] = useState(query.hidden);
  const [allCuisines, setAllCuisines] = useState(false);
  const [moreOpen, setMoreOpen] = useState(moreCount(query) > 0 || (signedIn && query.hidden));
  const [streetText, setStreetText] = useState("");
  const [counted, setCounted] = useState<{ key: string; facets: Facets | null } | null>(null);

  const draft: ResultsQuery = { ...query, kind, more, only, hidden };
  const key = resultsHref(draft);
  const type = typeForPath(kind);
  const picked = cuisinesOf(draft);

  // Counts for what's picked here, with the More filters' own counts.
  useEffect(() => {
    let cancelled = false;
    const t = setTimeout(() => {
      countFor(draft).then((f) => {
        if (!cancelled) setCounted({ key, facets: f });
      });
    }, 200);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
    // draft is captured through key.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const asked = counted && counted.key === key ? counted.facets : null;
  const shown: Facets | null = asked ?? (key === resultsHref(query) ? facets : null);
  const total = shown ? (shown.total ?? (picked.length === 1 ? shown.cuisines.find((c) => c.path === picked[0])?.n ?? 0 : shown.types[type ?? "all"] ?? 0)) : null;

  // The cuisines for the type picked: the most common nearby, A-Z; all of them A-Z on request.
  // (Finer kinds, such as Neapolitan under Pizza, are in the full list only.)
  const forType = useMemo(
    () => (shown?.cuisines ?? facets?.cuisines ?? []).filter((c) => type && typeForPath(c.path) === type),
    [shown, facets, type]
  );
  const cuisines = useMemo(() => {
    if (allCuisines) return [...forType].sort((a, b) => a.name.localeCompare(b.name));
    const top = forType
      .filter((c) => c.path.split(".").length === 2)
      .sort((a, b) => b.n - a.n)
      .slice(0, SHOWN_CUISINES);
    for (const p of picked) {
      if (!top.some((c) => c.path === p)) {
        const found = forType.find((c) => c.path === p);
        if (found) top.push(found);
      }
    }
    return top.sort((a, b) => a.name.localeCompare(b.name));
  }, [forType, allCuisines, picked]);
  const cuisineTotal = forType.length;

  function toggleCuisine(path: string) {
    const next = picked.includes(path) ? picked.filter((p) => p !== path) : [...picked, path];
    const patch = withCuisines(draft, next, type);
    setKind(patch.kind ?? null);
    setMore(patch.more ?? more);
  }

  function toggleOnly(k: Only) {
    if (!signedIn) {
      onLocked();
      return;
    }
    setOnly((o) => (o.includes(k) ? o.filter((x) => x !== k) : [...o, k]));
  }

  const streets = asked?.streets ?? [];
  const streetOn = more.street.trim();
  const streetChips =
    streetOn && !streets.some((s) => s.label.toLowerCase() === streetOn.toLowerCase())
      ? [{ street: streetOn.toLowerCase(), label: streetOn, n: undefined as number | undefined }, ...streets]
      : streets;
  const chain = asked?.chain;
  const moreOn = moreCount(draft) - (draft.more.list ? 1 : 0) + (signedIn && hidden ? 1 : 0);

  return (
    <div className="fixed inset-0 z-50 md:hidden" role="presentation">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="filters-h"
        className="absolute inset-x-0 bottom-0 top-12 flex flex-col rounded-t-[20px] bg-white shadow-[0_-4px_18px_rgba(0,0,0,0.15)]"
      >
        <span aria-hidden="true" className="mt-2 h-[5px] w-10 self-center rounded-full bg-[#d6d6d6]" />
        <div className="flex items-center justify-between border-b border-line px-2 pb-2 pt-1">
          <button type="button" aria-label="Close" onClick={onClose} className="flex h-11 w-11 items-center justify-center text-zinc-950">
            <Icon d="M18 6l-12 12M6 6l12 12" color="currentColor" size={22} />
          </button>
          <h2 id="filters-h" className="text-[17px] font-medium text-zinc-950">
            Filters
          </h2>
          <button
            type="button"
            onClick={() => {
              setKind(null);
              setOnly([]);
              setMore(NO_MORE);
            }}
            className="h-11 px-2.5 text-[15px] font-medium text-zinc-950 underline"
          >
            Clear all
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-4">
          <fieldset className="border-b border-[#f0f0f0] py-3">
            <legend className={legend}>Type</legend>
            <div className="clear-both flex flex-wrap gap-2">
              {TYPE_OPTIONS.map((t) => {
                const on = t.key === "all" ? !type : type === t.key;
                const n = shown?.types[t.key];
                return (
                  <button
                    key={t.key}
                    type="button"
                    aria-pressed={on}
                    onClick={() => {
                      setKind(t.key === "all" ? null : t.key);
                      setMore((m) => ({ ...m, cuisines: [] }));
                    }}
                    className={on ? chipOn : chipOff}
                  >
                    {t.label}
                    {n !== undefined && <span className={on ? "opacity-80" : "text-zinc-500"}>{n.toLocaleString("en-US")}</span>}
                  </button>
                );
              })}
            </div>
          </fieldset>

          {type && cuisineTotal > 0 && (
            <fieldset className="border-b border-[#f0f0f0] py-3">
              <legend className={legend}>
                Cuisine <span className="text-sm font-normal text-muted">· pick any number</span>
              </legend>
              <div className="clear-both flex flex-wrap gap-2">
                {cuisines.map((c) => {
                  const on = picked.includes(c.path);
                  return (
                    <button key={c.path} type="button" aria-pressed={on} onClick={() => toggleCuisine(c.path)} className={on ? chipKind : chipOff}>
                      {c.name}
                      <span className={on ? "opacity-80" : "text-zinc-500"}>{c.n.toLocaleString("en-US")}</span>
                    </button>
                  );
                })}
              </div>
              {(allCuisines || cuisineTotal > cuisines.length) && (
                <button type="button" onClick={() => setAllCuisines((a) => !a)} className="mt-2.5 h-10 text-sm font-medium text-zinc-950 underline">
                  {allCuisines ? "Fewer cuisines" : `All ${cuisineTotal} cuisines`}
                </button>
              )}
            </fieldset>
          )}

          <fieldset className="border-b border-[#f0f0f0] pb-2 pt-1">
            <legend className="float-left w-full pb-0.5 pt-3.5 text-base font-medium text-zinc-950">Show only</legend>
            <div className="clear-both">
              {SHOW_ONLY.map((s) => {
                const on = signedIn && only.includes(s.key);
                const n = signedIn ? shown?.[s.key] : undefined;
                return (
                  <label key={s.key} className="flex min-h-12 cursor-pointer items-center gap-3 text-base text-zinc-950">
                    <input type="checkbox" checked={on} onChange={() => toggleOnly(s.key)} className="h-6 w-6 shrink-0 accent-zinc-950" />
                    <Icon d={s.d} color={s.color} />
                    <span className="flex-1">{s.label}</span>
                    {signedIn ? (
                      n !== undefined && <span className="text-sm text-muted">{n.toLocaleString("en-US")}</span>
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
                <div className="flex min-h-12 items-center gap-3">
                  <label htmlFor="fs-list" className="flex-1 text-base text-zinc-950">
                    On one of your lists
                  </label>
                  <select
                    id="fs-list"
                    value={more.list ?? ""}
                    onChange={(e) => setMore((m) => ({ ...m, list: e.target.value || null }))}
                    className="h-11 max-w-[170px] rounded-[10px] border border-[#dddddd] bg-white px-2.5 text-[15px] text-zinc-950"
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

          <button
            type="button"
            aria-expanded={moreOpen}
            onClick={() => setMoreOpen((o) => !o)}
            className="flex h-[52px] w-full items-center justify-between border-b border-[#f0f0f0] text-base font-medium text-zinc-950"
          >
            More filters
            <span className="flex items-center gap-1.5 text-sm font-normal text-muted">
              {moreOn > 0 && `${moreOn} on`}
              <Icon d={moreOpen ? "M6 15l6 -6l6 6" : "M6 9l6 6l6 -6"} color="currentColor" size={18} />
            </span>
          </button>

          {moreOpen && (
            <>
              <fieldset className="border-b border-[#f0f0f0] py-3">
                <legend className={legend}>Street</legend>
                <div className="clear-both flex flex-wrap gap-2">
                  {streetChips.map((s) => {
                    const on = streetOn.toLowerCase() === s.label.toLowerCase();
                    return (
                      <button
                        key={s.street}
                        type="button"
                        aria-pressed={on}
                        onClick={() => setMore((m) => ({ ...m, street: on ? "" : s.label }))}
                        className={on ? chipKind : chipOff}
                      >
                        {s.label}
                        {s.n !== undefined && <span className={on ? "opacity-80" : "text-zinc-500"}>{s.n.toLocaleString("en-US")}</span>}
                      </button>
                    );
                  })}
                </div>
                <label htmlFor="fs-street" className="sr-only">
                  Another street
                </label>
                <input
                  id="fs-street"
                  type="text"
                  value={streetText}
                  placeholder="Another street"
                  autoComplete="off"
                  enterKeyHint="done"
                  onChange={(e) => setStreetText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && streetText.trim()) {
                      setMore((m) => ({ ...m, street: streetText.trim() }));
                      setStreetText("");
                    }
                  }}
                  className="mt-2.5 h-[46px] w-full rounded-[10px] border border-[#dddddd] bg-white px-3 text-base text-zinc-950 placeholder:text-zinc-500 focus:border-zinc-500 focus:outline-none"
                />
              </fieldset>

              <div className="flex items-center justify-between gap-3 border-b border-[#f0f0f0] py-3.5">
                <span className="text-base font-medium text-zinc-950">Search area</span>
                <button
                  type="button"
                  onClick={() => onDraw({ kind, only, more, hidden })}
                  className="inline-flex h-11 items-center gap-2 rounded-[10px] border border-[#dddddd] px-3.5 text-sm font-medium text-zinc-950"
                >
                  <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M12 5m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M19 8m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M5 11m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M15 19m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0M6.5 9.5l3.5 -3M14 5.5l3 1.5M18.5 10l-2.5 7M13.5 17.5l-7 -5" />
                  </svg>
                  {more.area ? "Draw again" : "Draw an area"}
                </button>
              </div>

              <fieldset className="border-b border-[#f0f0f0] py-3">
                <legend className={legend}>Chain or independent</legend>
                <div role="radiogroup" aria-label="Chain or independent" className="clear-both flex gap-0.5 rounded-xl border border-[#dddddd] p-[3px]">
                  {(
                    [
                      [null, "Any", chain ? chain.chain + chain.independent : undefined],
                      ["independent", "Independent", chain?.independent],
                      ["chain", "Chains", chain?.chain],
                    ] as [Chain | null, string, number | undefined][]
                  ).map(([value, label, n]) => {
                    const on = more.chain === value;
                    return (
                      <button
                        key={label}
                        type="button"
                        role="radio"
                        aria-checked={on}
                        onClick={() => setMore((m) => ({ ...m, chain: value }))}
                        className={`h-10 flex-1 rounded-[9px] text-sm font-medium ${on ? "bg-primary text-white" : "text-muted"}`}
                      >
                        {label} {n !== undefined && <span className={on ? "opacity-75" : "text-zinc-500"}>{n.toLocaleString("en-US")}</span>}
                      </button>
                    );
                  })}
                </div>
                <p className="mt-2 text-[13px] text-muted">A chain is a name with 10 or more places nationwide.</p>
              </fieldset>

              <fieldset className="pb-2 pt-1">
                <legend className="float-left w-full pb-0.5 pt-3.5 text-base font-medium text-zinc-950">Details</legend>
                <div className="clear-both">
                  {(
                    [
                      ["website", "Has a website", asked?.website],
                      ["phone", "Has a phone number", asked?.phone],
                      ["closed", "Include places that have closed", asked?.closed],
                    ] as ["website" | "phone" | "closed", string, number | undefined][]
                  ).map(([k, label, n]) => (
                    <label key={k} className="flex min-h-12 cursor-pointer items-center gap-3 text-base text-zinc-950">
                      <input
                        type="checkbox"
                        checked={more[k]}
                        onChange={() => setMore((m) => ({ ...m, [k]: !m[k] }))}
                        className="h-6 w-6 shrink-0 accent-zinc-950"
                      />
                      <span className="flex-1">{label}</span>
                      {n !== undefined && <span className="text-sm text-muted">{k === "closed" ? `+${n.toLocaleString("en-US")}` : n.toLocaleString("en-US")}</span>}
                    </label>
                  ))}
                  {signedIn && (
                    <label className="flex min-h-12 cursor-pointer items-center gap-3 text-base text-zinc-950">
                      <input type="checkbox" checked={hidden} onChange={() => setHidden((h) => !h)} className="h-6 w-6 shrink-0 accent-zinc-950" />
                      <span className="flex-1">Include places you hid</span>
                      {/* Counted only while they're left out. */}
                      {!hidden && shown && <span className="text-sm text-muted">+{shown.hidden.toLocaleString("en-US")}</span>}
                    </label>
                  )}
                </div>
              </fieldset>
            </>
          )}
        </div>

        <div className="border-t border-line bg-white px-4 pb-6 pt-3">
          <button
            type="button"
            onClick={() => {
              onApply({ kind, only, more, hidden });
              onClose();
            }}
            className="h-[52px] w-full rounded-xl bg-primary text-base font-medium text-white"
          >
            {total === null ? "Show places" : total === 0 ? "No places match" : `Show ${total.toLocaleString("en-US")} ${total === 1 ? "place" : "places"}`}
          </button>
        </div>
      </section>
    </div>
  );
}
