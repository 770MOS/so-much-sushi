"use client";

import { DRAWN_AREA_LABEL, MAP_AREA_LABEL, moreCount, NO_MORE, type MoreFilters, type ResultsQuery } from "@/lib/resultsQuery";
import type { ListOption } from "@/components/results/AllFiltersPanel";

// The All filters panel's choices that aren't on the bar already, as chips under it, each with
// × to take it off, and Clear all (mocked 2026-11-19). Cuisines show on the bar's Cuisine chip.
export default function MoreChips({
  query,
  lists,
  signedIn,
  onChange,
}: {
  query: ResultsQuery;
  lists: ListOption[];
  signedIn: boolean;
  onChange: (patch: Partial<ResultsQuery>) => void;
}) {
  // Showing hidden places is a signed-in person's choice; it does nothing for a visitor.
  const hiddenOn = signedIn && query.hidden;
  if (moreCount(query) === 0 && !hiddenOn) return null;
  const m = query.more;
  const listName = m.list ? lists.find((l) => l.id === m.list)?.name : null;
  // Taking the drawn area off leaves its box, as a map area.
  const where = query.where === DRAWN_AREA_LABEL ? MAP_AREA_LABEL : query.where;
  const chips: { label: string; off: Partial<MoreFilters>; hidden?: boolean }[] = [];
  if (m.area) chips.push({ label: "Drawn area", off: { area: null } });
  if (m.street.trim()) chips.push({ label: `On ${m.street.trim()}`, off: { street: "" } });
  if (m.chain === "independent") chips.push({ label: "Independent", off: { chain: null } });
  if (m.chain === "chain") chips.push({ label: "Chains only", off: { chain: null } });
  if (m.website) chips.push({ label: "Has a website", off: { website: false } });
  if (m.phone) chips.push({ label: "Has a phone number", off: { phone: false } });
  if (m.closed) chips.push({ label: "Closed places too", off: { closed: false } });
  if (m.list) chips.push({ label: listName ? `On “${listName}”` : "On one of your lists", off: { list: null } });
  if (m.close && query.q.trim()) chips.push({ label: "Close spellings", off: { close: false } });
  if (hiddenOn) chips.push({ label: "Hidden places too", off: {}, hidden: true });

  return (
    <div role="group" aria-label="Other filters on" className="flex flex-wrap items-center gap-2 border-b border-line px-4 pb-2.5 pt-0.5 md:px-6">
      {chips.map((chip) => (
        <span key={chip.label} className="inline-flex h-8 items-center gap-1 rounded-full bg-[#f3f3f3] pl-3 pr-1 text-[13px] font-medium text-zinc-950">
          {chip.label}
          <button
            type="button"
            aria-label={`Remove: ${chip.label}`}
            onClick={() =>
              onChange(chip.hidden ? { hidden: false } : { more: { ...m, ...chip.off }, ...(chip.off.area === null ? { where } : {}) })
            }
            className="flex h-7 w-7 items-center justify-center rounded-full text-muted hover:bg-zinc-200 hover:text-zinc-950"
          >
            <svg viewBox="0 0 24 24" width={14} height={14} fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" aria-hidden="true">
              <path d="M18 6l-12 12M6 6l12 12" />
            </svg>
          </button>
        </span>
      ))}
      <button
        type="button"
        onClick={() => onChange({ more: { ...NO_MORE, cuisines: m.cuisines }, where, hidden: false })}
        className="h-8 px-1.5 text-[13px] font-medium text-zinc-950 underline"
      >
        Clear all
      </button>
    </div>
  );
}
