"use client";

import { useEffect, useMemo, useState } from "react";
import { HEART_PATH, THUMB_PATH } from "@/components/icons";
import { TYPE_OPTIONS, typeForPath } from "@/lib/entityTypes";
import type { Only, ResultsQuery } from "@/lib/resultsQuery";
import type { Facets } from "@/lib/searchTypes";

// The phone's filters sheet (mocked 2026-11-12): type, cuisine (the most common nearby, shown
// A-Z with their counts, then "All N cuisines"), and Show only (your favorites, friends'
// favorites, Want to try). Nothing changes until "Show N places", which counts the choices
// made here for the same area and name.

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

type Props = {
  query: ResultsQuery;
  facets: Facets | null;
  signedIn: boolean;
  // The counts for other choices in the same area and name.
  countFor: (kind: string | null, only: Only[]) => Promise<Facets | null>;
  onApply: (patch: Partial<ResultsQuery>) => void;
  onLocked: () => void;
  onClose: () => void;
};

export default function FiltersSheet({ query, facets, signedIn, countFor, onApply, onLocked, onClose }: Props) {
  const [kind, setKind] = useState<string | null>(query.kind);
  const [only, setOnly] = useState<Only[]>(query.only);
  const [allCuisines, setAllCuisines] = useState(false);
  const [counted, setCounted] = useState<{ key: string; facets: Facets | null } | null>(null);

  const type = typeForPath(kind);
  const cuisine = kind && kind.includes(".") ? kind : null;
  const key = `${kind ?? ""}|${[...only].sort().join(",")}`;
  const applied = `${query.kind ?? ""}|${[...query.only].sort().join(",")}`;

  // Counts for what's picked here: the page's own while nothing has changed, else asked for.
  useEffect(() => {
    if (key === applied) return;
    let cancelled = false;
    const t = setTimeout(() => {
      countFor(kind, only).then((f) => {
        if (!cancelled) setCounted({ key, facets: f });
      });
    }, 200);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
    // countFor is a new function each render; kind and only are in key.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, applied]);

  const shown: Facets | null = key === applied ? facets : counted && counted.key === key ? counted.facets : null;
  const total = shown ? (cuisine ? shown.cuisines.find((c) => c.path === cuisine)?.n ?? 0 : shown.types[type ?? "all"] ?? 0) : null;

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
    if (cuisine && !top.some((c) => c.path === cuisine)) {
      const picked = forType.find((c) => c.path === cuisine);
      if (picked) top.push(picked);
    }
    return top.sort((a, b) => a.name.localeCompare(b.name));
  }, [forType, allCuisines, cuisine]);
  const cuisineTotal = forType.length;

  function toggleOnly(k: Only) {
    if (!signedIn) {
      onLocked();
      return;
    }
    setOnly((o) => (o.includes(k) ? o.filter((x) => x !== k) : [...o, k]));
  }

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
            }}
            className="h-11 px-2.5 text-[15px] font-medium text-zinc-950 underline"
          >
            Clear all
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-4">
          <fieldset className="border-b border-[#f0f0f0] py-3">
            <legend className="float-left w-full pb-2.5 pt-3 text-base font-medium text-zinc-950">Type</legend>
            <div className="clear-both flex flex-wrap gap-2">
              {TYPE_OPTIONS.map((t) => {
                const on = t.key === "all" ? !type : type === t.key;
                const n = shown?.types[t.key];
                return (
                  <button key={t.key} type="button" aria-pressed={on} onClick={() => setKind(t.key === "all" ? null : t.key)} className={on ? chipOn : chipOff}>
                    {t.label}
                    {n !== undefined && <span className={on ? "opacity-80" : "text-zinc-500"}>{n.toLocaleString("en-US")}</span>}
                  </button>
                );
              })}
            </div>
          </fieldset>

          {type && cuisineTotal > 0 && (
            <fieldset className="border-b border-[#f0f0f0] py-3">
              <legend className="float-left w-full pb-2.5 pt-3 text-base font-medium text-zinc-950">
                Cuisine <span className="text-sm font-normal text-muted">· nearby counts</span>
              </legend>
              <div className="clear-both flex flex-wrap gap-2">
                {cuisines.map((c) => {
                  const on = cuisine === c.path;
                  return (
                    <button key={c.path} type="button" aria-pressed={on} onClick={() => setKind(on ? type : c.path)} className={on ? chipKind : chipOff}>
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

          <fieldset className="pb-2 pt-1">
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
            </div>
          </fieldset>
        </div>

        <div className="border-t border-line bg-white px-4 pb-6 pt-3">
          <button
            type="button"
            onClick={() => {
              onApply({ kind, only });
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
