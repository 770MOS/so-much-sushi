"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import dynamic from "next/dynamic";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import StatusBadge from "@/components/StatusBadge";
import { FavoriteIcon, FriendsFavoriteIcon } from "@/components/icons";
import { friendsLabel, kindLabel } from "@/components/results/ResultRow";
import type { MapMarkerEntity } from "@/components/EntityMap";
import { boxForPlaces, formatMiles, type ListPlace } from "@/lib/lists";
import { milesBetween } from "@/lib/placeDetail";
import { placeIdFromPath, setSheetStart } from "@/lib/placePanel";
import { topLevelTypeForCategoryPaths, TYPE_OPTIONS, type EntityType } from "@/lib/entityTypes";
import { useIsDesktop } from "@/lib/useIsDesktop";
import type { HerePoint } from "@/lib/useHerePoint";
import type { Box } from "@/lib/resultsQuery";

const ResultsMap = dynamic(() => import("@/components/results/ResultsMap"), { ssr: false });

// The list-and-map layout shared by the Favorites page and a single list (mocked 2026-11-12):
// the same List · Split · Map views as search, a column of places with a map beside it, and
// the place panel (or phone sheet) when a place is opened. Everything is worked out here from
// the places given (a favorites page or a list holds them all), nearest to the viewer first.

type View = "list" | "split" | "map";
type Sort = "nearest" | "az";
type Type = Exclude<EntityType, "all">;

export type BrowserPlace = ListPlace & { miles: number | null };

type Props = {
  places: ListPlace[] | null; // null while loading
  here: HerePoint | null | undefined;
  // The top of the column: title and summary. Gets the counts after filters.
  heading: (shown: BrowserPlace[], sort: Sort) => ReactNode;
  // Left end of the bar above the list and map (a list's back link and buttons).
  toolbar?: ReactNode;
  // Type buttons and a town menu, with counts (the Favorites page).
  filters?: boolean;
  // Rows grouped under their town (the Favorites page).
  groupByTown?: boolean;
  // A small heart before the name of places that are also the viewer's favorites (a list).
  heartBadge?: boolean;
  // Buttons at the end of each row.
  rowEnd?: (p: BrowserPlace) => ReactNode;
  // A line under a place (e.g. "Also your favorite"); friends' names are left out when false.
  rowNote?: (p: BrowserPlace) => ReactNode;
  showFriends?: boolean;
  empty: ReactNode;
  footer?: ReactNode;
  // The map's label for its places, e.g. "favorites".
  mapNoun: string;
};

const chipBase =
  "inline-flex h-10 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-sm font-medium transition-colors";
const chipOff = `${chipBase} border border-[#dddddd] bg-white text-zinc-950 hover:border-zinc-400`;
const chipOn = `${chipBase} border border-primary bg-primary text-white`;

function Chevron({ size = 16 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M6 9l6 6l6 -6" />
    </svg>
  );
}

function MapIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 7l6 -3l6 3l6 -3v13l-6 3l-6 -3l-6 3v-13M9 4v13M15 7v13" />
    </svg>
  );
}

function ListIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 6h11M9 12h11M9 18h11M5 6v.01M5 12v.01M5 18v.01" />
    </svg>
  );
}

// A town: its name, with the state when two towns share a name.
type Town = { key: string; label: string };
function townOf(p: ListPlace): Town | null {
  if (!p.city) return null;
  return { key: `${p.city}|${p.state ?? ""}`, label: p.city };
}

function TownMenu({ towns, value, onChange }: { towns: { key: string; label: string; n: number }[]; value: string | null; onChange: (key: string | null) => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
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
  const current = towns.find((t) => t.key === value);
  if (towns.length < 2 && !current) return null;
  return (
    <div ref={ref} className="relative shrink-0">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className={current ? `${chipBase} border-[1.5px] border-link bg-[#eef2fb] pr-3 text-link` : `${chipOff} pr-3`}
      >
        <span className={current ? "" : "text-muted"}>Town:</span>
        {current ? current.label : "All"}
        <Chevron />
      </button>
      {open && (
        <ul role="listbox" aria-label="Town" className="absolute left-0 top-full z-30 mt-2 max-h-80 w-64 overflow-y-auto rounded-xl border border-line bg-white py-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]">
          <li role="option" aria-selected={!current}>
            <button
              type="button"
              onClick={() => {
                setOpen(false);
                onChange(null);
              }}
              className={`flex min-h-11 w-full items-center px-3 text-left text-[15px] hover:bg-zinc-50 ${!current ? "font-medium" : ""}`}
            >
              All towns
            </button>
          </li>
          {towns.map((t) => (
            <li key={t.key} role="option" aria-selected={value === t.key}>
              <button
                type="button"
                onClick={() => {
                  setOpen(false);
                  onChange(t.key);
                }}
                className={`flex min-h-11 w-full items-center justify-between gap-3 px-3 text-left text-[15px] hover:bg-zinc-50 ${value === t.key ? "font-medium text-link" : "text-zinc-950"}`}
              >
                <span>{t.label}</span>
                <span className="text-[13px] font-normal text-zinc-500">{t.n.toLocaleString("en-US")}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function SortSelect({ sort, onChange, canNearest }: { sort: Sort; onChange: (s: Sort) => void; canNearest: boolean }) {
  return (
    <label className="relative inline-flex shrink-0">
      <span className="sr-only">Sort</span>
      <select
        value={sort}
        onChange={(e) => onChange(e.target.value === "az" ? "az" : "nearest")}
        className="h-10 appearance-none bg-transparent pl-1 pr-6 text-sm font-medium text-zinc-950 focus:outline-none"
      >
        {canNearest && <option value="nearest">Nearest first</option>}
        <option value="az">Name A–Z</option>
      </select>
      <span className="pointer-events-none absolute right-1 top-3">
        <Chevron />
      </span>
    </label>
  );
}

function PlaceRow({
  p,
  heartBadge,
  street,
  end,
  note,
  showFriends,
  highlighted,
  selected,
  onOpen,
  onHover,
}: {
  p: BrowserPlace;
  heartBadge: boolean;
  street: boolean;
  end?: ReactNode;
  note?: ReactNode;
  showFriends: boolean;
  highlighted: boolean;
  selected: boolean;
  onOpen: (id: string) => void;
  onHover: (id: string | null) => void;
}) {
  const kind = kindLabel(p);
  const friends = showFriends ? friendsLabel(p.recommended_by, p.recommended_count) : null;
  const where = street ? p.street ?? p.address : p.address;
  return (
    <li
      data-place-id={p.id}
      onMouseEnter={() => onHover(p.id)}
      onMouseLeave={() => onHover(null)}
      className={`flex items-center gap-1 border-b border-[#f0f0f0] py-2.5 pl-5 pr-2 md:pl-6 ${highlighted ? "bg-[#f3f6fd]" : ""}`}
    >
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex items-baseline justify-between gap-3">
          <span className="flex min-w-0 items-center gap-1.5">
            {heartBadge && p.is_starred && (
              <span role="img" aria-label="One of your favorites" className="shrink-0 self-center">
                <FavoriteIcon filled size={15} />
              </span>
            )}
            <Link
              href={`/venue/${p.id}`}
              aria-current={selected ? "true" : undefined}
              onClick={(e) => {
                if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
                e.preventDefault();
                onOpen(p.id);
              }}
              className="truncate text-base font-medium text-zinc-950 hover:underline"
            >
              {p.name}
            </Link>
          </span>
          {p.miles !== null && <span className="shrink-0 text-sm text-muted">{formatMiles(p.miles)}</span>}
        </div>
        <p className="truncate text-[13px] text-muted">
          {kind && <span className="font-medium text-link">{kind}</span>}
          {kind && where ? " · " : ""}
          {where}
        </p>
        <StatusBadge status={p.status} />
        {friends && (
          <p className="flex items-center gap-1.5 text-[13px] font-medium text-friends-ink">
            <FriendsFavoriteIcon size={13} />
            <span className="truncate">{friends}</span>
          </p>
        )}
        {note}
      </div>
      {end && <div className="flex shrink-0 items-center">{end}</div>}
    </li>
  );
}

export default function PlacesBrowser({ places, here, heading, toolbar, filters, groupByTown, heartBadge, rowEnd, rowNote, showFriends = true, empty, footer, mapNoun }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const selectedId = placeIdFromPath(pathname);
  const isDesktop = useIsDesktop();
  const [view, setView] = useState<View>("split");
  const [phoneMap, setPhoneMap] = useState(false);
  const [sortChoice, setSortChoice] = useState<Sort | null>(null);
  const [type, setType] = useState<Type | null>(null);
  const [town, setTown] = useState<string | null>(null);
  const [hoverId, setHoverId] = useState<string | null>(null);

  const sort: Sort = sortChoice ?? (here ? "nearest" : "az");

  const withMiles: BrowserPlace[] = useMemo(
    () => (places ?? []).map((p) => ({ ...p, miles: here ? milesBetween(here, p) : null })),
    [places, here]
  );

  // Towns, with the state added where two share a name.
  const townLabels = useMemo(() => {
    const byKey = new Map<string, Town>();
    for (const p of withMiles) {
      const t = townOf(p);
      if (t) byKey.set(t.key, t);
    }
    const names = new Map<string, number>();
    for (const t of byKey.values()) names.set(t.label, (names.get(t.label) ?? 0) + 1);
    const out = new Map<string, string>();
    for (const t of byKey.values()) {
      const state = t.key.split("|")[1];
      out.set(t.key, (names.get(t.label) ?? 0) > 1 && state ? `${t.label}, ${state}` : t.label);
    }
    return out;
  }, [withMiles]);

  const typeOf = useCallback((p: ListPlace) => topLevelTypeForCategoryPaths(p.category_paths), []);
  const inTown = useCallback((p: ListPlace) => !town || townOf(p)?.key === town, [town]);
  const ofType = useCallback((p: ListPlace) => !type || typeOf(p) === type, [type, typeOf]);

  // Each count leaves out its own filter, as on the results page.
  const typeCounts = useMemo(() => {
    const counts: Record<string, number> = { all: 0 };
    for (const p of withMiles) {
      if (!inTown(p)) continue;
      counts.all += 1;
      const t = typeOf(p);
      if (t) counts[t] = (counts[t] ?? 0) + 1;
    }
    return counts;
  }, [withMiles, inTown, typeOf]);
  const townCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const p of withMiles) {
      if (!ofType(p)) continue;
      const t = townOf(p);
      if (t) counts.set(t.key, (counts.get(t.key) ?? 0) + 1);
    }
    return [...counts.entries()]
      .map(([key, n]) => ({ key, n, label: townLabels.get(key) ?? key }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [withMiles, ofType, townLabels]);

  const shown = useMemo(() => {
    const rows = withMiles.filter((p) => inTown(p) && ofType(p));
    return rows.sort((a, b) =>
      sort === "nearest" && a.miles !== null && b.miles !== null ? a.miles - b.miles || a.name.localeCompare(b.name) : a.name.localeCompare(b.name)
    );
  }, [withMiles, inTown, ofType, sort]);

  const groups = useMemo(() => {
    if (!groupByTown) return null;
    const byKey = new Map<string, { key: string; label: string; rows: BrowserPlace[] }>();
    for (const p of shown) {
      const t = townOf(p);
      const key = t?.key ?? "";
      if (!byKey.has(key)) byKey.set(key, { key, label: t ? townLabels.get(t.key) ?? t.label : "Other places", rows: [] });
      byKey.get(key)!.rows.push(p);
    }
    // Rows are already in order, so each town's first row decides where the town goes
    // (nearest first, or A-Z by town); places with no town come last.
    const list = [...byKey.values()];
    if (sort === "az") list.sort((a, b) => (a.key === "" ? 1 : b.key === "" ? -1 : a.label.localeCompare(b.label)));
    else list.sort((a, b) => (a.key === "" ? 1 : b.key === "" ? -1 : 0));
    return list;
  }, [groupByTown, shown, townLabels, sort]);

  const markers: MapMarkerEntity[] = useMemo(
    () =>
      shown.map((p) => ({
        id: p.id,
        name: p.name,
        address: p.address,
        lat: p.lat,
        lng: p.lng,
        matchesFilter: true,
        isStarred: p.is_starred,
        recommendedCount: p.recommended_count,
        isWant: p.is_want,
        status: p.status,
        entityType: topLevelTypeForCategoryPaths(p.category_paths),
      })),
    [shown]
  );

  // The map shows all the places on screen; it moves only when that set's edges change.
  const box = boxForPlaces(shown);
  const boxKey = box ? [box.west, box.south, box.east, box.north].map((n) => n.toFixed(4)).join(",") : "";
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const area: Box | null = useMemo(() => box, [boxKey]);

  const openPlace = useCallback(
    (id: string) => {
      setSheetStart(isDesktop === false && phoneMap ? "peek" : "full");
      if (selectedId) router.replace(`/venue/${id}`, { scroll: false });
      else router.push(`/venue/${id}`, { scroll: false });
    },
    [isDesktop, phoneMap, selectedId, router]
  );

  // The open place's row stays in view.
  const listRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!selectedId) return;
    listRef.current?.querySelector(`[data-place-id="${selectedId}"]`)?.scrollIntoView({ block: "nearest" });
  }, [selectedId]);

  const row = (p: BrowserPlace) => (
    <PlaceRow
      key={p.id}
      p={p}
      heartBadge={Boolean(heartBadge)}
      street={Boolean(groupByTown)}
      end={rowEnd?.(p)}
      note={rowNote?.(p)}
      showFriends={showFriends}
      highlighted={hoverId === p.id || selectedId === p.id}
      selected={selectedId === p.id}
      onOpen={openPlace}
      onHover={setHoverId}
    />
  );

  const column = (
    <div ref={listRef}>
      {heading(shown, sort)}
      {places === null ? (
        <p className="px-6 py-10 text-center text-sm text-muted">Loading…</p>
      ) : places.length === 0 ? (
        <div className="px-6 py-10 text-center text-sm text-muted">{empty}</div>
      ) : shown.length === 0 ? (
        <div className="px-6 py-10 text-center text-sm text-muted">
          None of these match.{" "}
          <button
            type="button"
            onClick={() => {
              setType(null);
              setTown(null);
            }}
            className="font-medium text-zinc-950 underline"
          >
            Show all
          </button>
        </div>
      ) : groups ? (
        groups.map((g) => (
          <section key={g.key} aria-label={g.label}>
            <h2 className="border-b border-[#f0f0f0] px-5 pb-1.5 pt-3.5 text-sm font-medium text-muted md:px-6">
              {g.label} · {g.rows.length}
            </h2>
            <ul>{g.rows.map(row)}</ul>
          </section>
        ))
      ) : (
        <ul>{shown.map(row)}</ul>
      )}
      {footer}
    </div>
  );

  const map = (className: string) =>
    area ? (
      <ResultsMap
        places={markers}
        cells={null}
        area={area}
        highlightId={hoverId}
        selectedId={selectedId}
        onSelect={openPlace}
        revealInset={isDesktop ? { right: 440, bottom: 0 } : { right: 0, bottom: Math.round((typeof window === "undefined" ? 800 : window.innerHeight) * 0.46) }}
        className={className}
      >
        <p className="sr-only" aria-live="polite">
          {shown.length} {mapNoun} on the map
        </p>
      </ResultsMap>
    ) : (
      <div className={`${className} flex items-center justify-center bg-[#f1f2ef] text-sm text-muted`}>
        {places === null ? "Loading…" : `No ${mapNoun} to show on the map`}
      </div>
    );

  const viewSwitch = (
    <div role="group" aria-label="View" className="flex gap-0.5 rounded-xl border border-[#dddddd] p-[3px]">
      {(["list", "split", "map"] as View[]).map((v) => (
        <button
          key={v}
          type="button"
          aria-pressed={view === v}
          onClick={() => setView(v)}
          className={`h-[34px] rounded-[9px] px-3 text-sm font-medium ${view === v ? "bg-primary text-white" : "text-muted hover:text-zinc-950"}`}
        >
          {v === "list" ? "List" : v === "split" ? "Split" : "Map"}
        </button>
      ))}
    </div>
  );

  const filterChips = filters && (places?.length ?? 0) > 0 && (
    <>
      <div role="group" aria-label="Type of place" className="flex gap-2">
        {TYPE_OPTIONS.map((t) => {
          const on = t.key === "all" ? !type : type === t.key;
          const n = typeCounts[t.key] ?? 0;
          if (t.key !== "all" && n === 0 && !on) return null;
          return (
            <button key={t.key} type="button" aria-pressed={on} onClick={() => setType(t.key === "all" ? null : t.key)} className={on ? chipOn : chipOff}>
              {t.label}
              <span className={on ? "opacity-80" : "text-zinc-500"}>{n.toLocaleString("en-US")}</span>
            </button>
          );
        })}
      </div>
      {townCounts.length > 1 || town ? <span aria-hidden="true" className="mx-1 h-6 w-px shrink-0 bg-[#dddddd]" /> : null}
      <TownMenu towns={townCounts} value={town} onChange={setTown} />
    </>
  );

  const bar = (
    <div data-place-panel-top>
      <div className="flex flex-col gap-2 border-b border-line px-4 py-2.5 md:flex-row md:flex-wrap md:items-center md:gap-2 md:px-6">
        {(toolbar || filterChips) && (
          <div className="-mx-4 flex items-center gap-2 overflow-x-auto px-4 pb-0.5 md:contents">
            {toolbar}
            {filterChips}
          </div>
        )}
        <div className="flex items-center justify-between gap-2.5 md:ml-auto">
          <SortSelect sort={sort} onChange={setSortChoice} canNearest={Boolean(here)} />
          <div className="hidden md:flex">{viewSwitch}</div>
        </div>
      </div>
    </div>
  );

  return (
    <main className="flex flex-1 flex-col">
      {bar}

      {isDesktop === false && (
        <div>
          {phoneMap ? map("h-[calc(100dvh-230px)] w-full") : column}
          {(places?.length ?? 0) > 0 && (
            <button
              type="button"
              onClick={() => setPhoneMap((m) => !m)}
              className="fixed bottom-[92px] left-1/2 z-10 inline-flex h-12 -translate-x-1/2 items-center gap-2 rounded-full bg-primary px-5 text-[15px] font-medium text-white shadow-[0_4px_14px_rgba(0,0,0,0.25)]"
            >
              {phoneMap ? <ListIcon /> : <MapIcon />}
              {phoneMap ? "List" : "Map"}
            </button>
          )}
        </div>
      )}

      {isDesktop && (
        <div>
          {view === "list" && <div className="mx-auto w-full max-w-3xl">{column}</div>}
          {view === "split" && (
            <div className="flex items-start">
              <section aria-label="Places" className="w-[440px] shrink-0 border-r border-line">
                {column}
              </section>
              <section aria-label="Map" className="sticky top-0 h-[100dvh] min-w-0 flex-1">
                {map("h-full w-full")}
              </section>
            </div>
          )}
          {view === "map" && (
            <section aria-label="Map">
              {map("h-[calc(100dvh-140px)] min-h-[480px] w-full")}
            </section>
          )}
        </div>
      )}
    </main>
  );
}

