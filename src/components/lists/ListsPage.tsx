"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import JoinPanel from "@/components/lists/JoinPanel";
import NewListDialog from "@/components/lists/NewListDialog";
import { VisibilityIcon } from "@/components/lists/VisibilityMenu";
import { SortSelect } from "@/components/lists/PlacesBrowser";
import { FLAG_PATH, formatMiles, placeWord, townsLine, VISIBILITY, type ListCardData } from "@/lib/lists";
import { useUserId } from "@/lib/useSignedIn";
import { useHerePoint } from "@/lib/useHerePoint";

// The Lists page (mocked 2026-11-12): the person's own lists as cards, the ready-made Want to
// try first, each with its place count, towns, who can see it and how close its nearest place
// is, nearest first; then the lists friends share with them. Lists are just for organizing:
// they never count as favorites.

function Plus({ size = 18 }: { size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

// The card's small map: the list's places as dots where they sit relative to each other.
function CardMap({ points, want }: { points: [number, number][]; want: boolean }) {
  const dots = useMemo(() => {
    if (points.length === 0) return [];
    const lats = points.map((p) => p[0]);
    const lngs = points.map((p) => p[1]);
    const [south, north] = [Math.min(...lats), Math.max(...lats)];
    const [west, east] = [Math.min(...lngs), Math.max(...lngs)];
    return points.map(([lat, lng]) => ({
      x: east > west ? 12 + ((lng - west) / (east - west)) * 76 : 50,
      y: north > south ? 18 + ((north - lat) / (north - south)) * 64 : 50,
    }));
  }, [points]);
  return (
    <span aria-hidden="true" className="relative block h-32 overflow-hidden border-b border-[#f0f0f0] bg-[#f1f2ef]">
      <svg width="100%" height="128" viewBox="0 0 340 128" preserveAspectRatio="xMidYMid slice" className="absolute inset-0">
        <path d="M60 -10 L130 40 L170 70 L180 140" fill="none" stroke="#cbe1ee" strokeWidth="9" strokeLinecap="round" />
        <path d="M-10 90 L120 60 L350 30" fill="none" stroke="#ffffff" strokeWidth="5" />
        <path d="M-10 40 L350 100" fill="none" stroke="#ffffff" strokeWidth="4" />
        <path d="M-10 115 L140 80 L350 70" fill="none" stroke="#f7dfa9" strokeWidth="4" />
      </svg>
      {dots.map((d, i) => (
        <span
          key={i}
          className="absolute h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow-[0_1px_3px_rgba(0,0,0,0.3)]"
          style={{ left: `${d.x}%`, top: `${d.y}%`, background: want ? "#3b5bdb" : "#222222" }}
        />
      ))}
    </span>
  );
}

const AVATAR_COLORS = [
  ["#e7f4ec", "#17603a"],
  ["#e8eefb", "#2c4a9a"],
  ["#fbeef2", "#9c2c4e"],
  ["#f6efe3", "#7a5212"],
  ["#efe9f8", "#4b2f8a"],
];
function avatarColors(seed: string) {
  let h = 0;
  for (const c of seed) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

export default function ListsPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const params = useSearchParams();
  const userId = useUserId();
  const here = useHerePoint(userId);
  const [cards, setCards] = useState<{ key: string; rows: ListCardData[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [sortChoice, setSortChoice] = useState<"nearest" | "az" | null>(null);
  const [making, setMaking] = useState(params.get("new") === "1");

  const key = userId && here !== undefined ? `${userId}|${here?.lat ?? ""}|${here?.lng ?? ""}` : null;
  useEffect(() => {
    if (!key || !userId) return;
    let cancelled = false;
    supabase
      .rpc("lists_overview", here ? { ref_lat: here.lat, ref_lng: here.lng } : {})
      .then(({ data, error: err }) => {
        if (cancelled) return;
        if (err) setError("Something went wrong loading your lists. Try again in a moment.");
        setCards({ key, rows: (data as ListCardData[] | null) ?? [] });
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, supabase]);

  const sort = sortChoice ?? (here ? "nearest" : "az");
  const rows = cards && cards.key === key ? cards.rows : null;
  const order = (a: ListCardData, b: ListCardData) => {
    if (a.is_default !== b.is_default) return a.is_default ? -1 : 1;
    if (sort === "nearest") {
      const da = a.closest_miles ?? Infinity;
      const db = b.closest_miles ?? Infinity;
      if (da !== db) return da - db;
    }
    return a.name.localeCompare(b.name);
  };
  const mine = (rows ?? []).filter((c) => c.is_mine).sort(order);
  const theirs = (rows ?? []).filter((c) => !c.is_mine).sort(order);

  if (userId === undefined) return <main className="flex-1" />;
  if (userId === null) {
    return (
      <JoinPanel
        icon={
          <svg viewBox="0 0 24 24" width={28} height={28} fill="none" stroke="#3b5bdb" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
            <path d={FLAG_PATH} />
          </svg>
        }
        title="Lists come with a free account"
        body="Keep a Want to try list, and group places any way you like: date night, brunch, places for visitors. Share a list with friends, or with anyone."
      />
    );
  }

  return (
    <main className="mx-auto flex w-full max-w-[1200px] flex-1 flex-col gap-6 px-5 pb-14 pt-8 md:px-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-col gap-1">
          <h1 className="text-3xl font-medium tracking-tight text-zinc-950">Your lists</h1>
          <p className="text-[15px] text-muted">
            {rows ? `${mine.length} ${mine.length === 1 ? "list" : "lists"}. ` : ""}
            Lists are just for organizing; they never count as favorites.
          </p>
        </div>
        <div className="flex items-center gap-2.5">
          <SortSelect sort={sort} onChange={setSortChoice} canNearest={Boolean(here)} />
          <button
            type="button"
            onClick={() => setMaking(true)}
            className="inline-flex h-11 items-center gap-2 rounded-[10px] bg-primary px-4 text-[15px] font-medium text-white hover:bg-primary-hover"
          >
            <Plus />
            New list
          </button>
        </div>
      </div>

      {error && <p className="text-sm text-red-700">{error}</p>}

      {rows === null ? (
        <p className="py-10 text-center text-sm text-muted">Loading…</p>
      ) : (
        <ul className="grid gap-[18px] [grid-template-columns:repeat(auto-fill,minmax(min(100%,320px),1fr))]">
          {mine.map((c) => (
            <li key={c.id}>
              <Link href={`/lists/${c.id}`} className="flex h-full flex-col overflow-hidden rounded-[14px] border border-line text-zinc-950 hover:border-zinc-400">
                <CardMap points={c.points} want={c.is_default} />
                <span className="flex flex-1 flex-col gap-1.5 px-4 pb-4 pt-3.5">
                  <span className="flex items-center gap-2 text-[17px] font-medium">
                    {c.is_default && (
                      <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#3b5bdb" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <path d={FLAG_PATH} />
                      </svg>
                    )}
                    <span className="truncate">{c.name}</span>
                    {c.is_default && <span className="ml-auto shrink-0 text-xs font-normal text-[#707070]">Ready-made</span>}
                  </span>
                  <span className="text-sm text-muted">
                    {c.place_count} {placeWord(c.place_count)}
                    {c.towns.length > 0 && ` · ${townsLine(c.towns, c.town_count)}`}
                  </span>
                  <span className="mt-auto flex items-center justify-between gap-2.5 pt-1.5 text-[13px] text-muted">
                    <span className="inline-flex items-center gap-1.5">
                      <VisibilityIcon v={c.visibility} />
                      {VISIBILITY[c.visibility].label}
                    </span>
                    {c.closest_miles !== null && <span>Closest {formatMiles(Number(c.closest_miles))}</span>}
                  </span>
                </span>
              </Link>
            </li>
          ))}
          <li>
            <button
              type="button"
              onClick={() => setMaking(true)}
              className="flex h-full min-h-[230px] w-full flex-col items-center justify-center gap-2 rounded-[14px] border-[1.5px] border-dashed border-[#cccccc] bg-white text-base font-medium text-zinc-950 hover:border-zinc-400"
            >
              <Plus size={26} />
              New list
              <span className="text-sm font-normal text-muted">Group places any way you like</span>
            </button>
          </li>
        </ul>
      )}

      {theirs.length > 0 && (
        <section aria-labelledby="shared-h" className="flex flex-col gap-3.5 pt-3">
          <h2 id="shared-h" className="text-xl font-medium text-zinc-950">
            Shared by your friends
          </h2>
          <ul className="border-t border-[#f0f0f0]">
            {theirs.map((c) => {
              const who = c.owner_name ?? "A friend";
              const [bg, fg] = avatarColors(c.owner_handle ?? who);
              return (
                <li key={c.id} className="border-b border-[#f0f0f0]">
                  <Link href={`/lists/${c.id}`} className="flex items-center gap-3.5 py-3.5 text-zinc-950">
                    <span aria-hidden="true" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-[15px] font-medium" style={{ background: bg, color: fg }}>
                      {who.trim().charAt(0).toUpperCase()}
                    </span>
                    <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                      <span className="truncate text-base font-medium">{c.name}</span>
                      <span className="truncate text-sm text-muted">
                        {who.split(/\s+/)[0]} · {c.place_count} {placeWord(c.place_count)}
                        {c.towns.length > 0 && ` · ${townsLine(c.towns, c.town_count)}`}
                      </span>
                    </span>
                    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#707070" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <path d="M9 6l6 6l-6 6" />
                    </svg>
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {making && (
        <NewListDialog
          userId={userId}
          onClose={() => setMaking(false)}
          onCreated={(id) => {
            setMaking(false);
            router.push(`/lists/${id}`);
          }}
        />
      )}
    </main>
  );
}
