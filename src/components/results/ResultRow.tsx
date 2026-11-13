"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import AddToListMenu from "@/components/AddToListMenu";
import StatusBadge from "@/components/StatusBadge";
import { FavoriteIcon, FriendsFavoriteIcon } from "@/components/icons";
import type { Recommender, SearchResult } from "@/lib/searchTypes";

// First names keep the line short ("Priya and Sam’s favorite"); the link goes to their page.
function Name({ who }: { who: Recommender }) {
  const label = who.name?.trim().split(/\s+/)[0] || "a friend";
  if (!who.handle) return <>{label}</>;
  return (
    <Link href={`/u/${who.handle}`} className="hover:underline">
      {label}
    </Link>
  );
}

// Friends who favorited a place, named up to three (decided 2026-11-12): "Priya’s favorite",
// "Priya and Sam’s favorite", "Priya, Sam and Dev’s favorite", "A favorite of Priya, Sam, Dev
// and 4 others".
export function friendsLabel(by: Recommender[] | null, count: number): ReactNode | null {
  if (!count) return null;
  const people = (by ?? []).slice(0, 3);
  while (people.length < Math.min(count, 3)) people.push({ name: "a friend", handle: null });
  const names = people.map((p, i) => <Name key={i} who={p} />);
  const joined =
    names.length === 1 ? (
      names[0]
    ) : names.length === 2 ? (
      <>
        {names[0]} and {names[1]}
      </>
    ) : (
      <>
        {names[0]}, {names[1]}
        {count > 3 ? ", " : " and "}
        {names[2]}
      </>
    );
  if (count <= 3) return <>{joined}’s favorite</>;
  const others = count - 3;
  return (
    <>
      A favorite of {joined} and {others} {others === 1 ? "other" : "others"}
    </>
  );
}

// The kind shown under a name: its finer kinds if it has any ("Italian, Pizza"), else its type.
export function kindLabel(r: SearchResult): string {
  const cats = r.categories ?? [];
  const finer = cats.slice(1, 3);
  return finer.length ? finer.join(", ") : cats[0] ?? "";
}

function RowMenu({ name, hidden, onToggleHide }: { name: string; hidden: boolean; onToggleHide: () => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, [open]);
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label={`More for ${name}`}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className="flex h-11 w-9 items-center justify-center rounded-lg text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" aria-hidden="true">
          <path d="M5 12h.01M12 12h.01M19 12h.01" />
        </svg>
      </button>
      {open && (
        <div role="menu" className="absolute right-0 z-20 mt-1 w-56 rounded-xl border border-line bg-white p-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]">
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onToggleHide();
            }}
            className="flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-zinc-950 hover:bg-zinc-100"
          >
            {hidden ? "Show in results again" : "Hide from my results"}
          </button>
        </div>
      )}
    </div>
  );
}

type Props = {
  r: SearchResult;
  card: boolean;
  starred: boolean;
  hidden: boolean;
  userId: string | null;
  onToggleStar: () => void;
  onToggleHide: () => void;
  onLocked: () => void;
  onHover?: (id: string | null) => void;
  highlighted?: boolean;
};

export default function ResultRow({ r, card, starred, hidden, userId, onToggleStar, onToggleHide, onLocked, onHover, highlighted }: Props) {
  const friends = friendsLabel(r.recommended_by, r.recommended_count);
  const kind = kindLabel(r);
  return (
    <li
      onMouseEnter={() => onHover?.(r.id)}
      onMouseLeave={() => onHover?.(null)}
      className={`flex items-center gap-1 ${
        card ? "rounded-xl border border-line px-4 py-3" : "border-b border-[#f0f0f0] py-2.5 pl-5 pr-2 md:pl-6"
      } ${highlighted ? "bg-[#f3f6fd]" : ""} ${hidden ? "opacity-60" : ""}`}
    >
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex items-baseline justify-between gap-3">
          <Link href={`/venue/${r.id}`} className="truncate text-base font-medium text-zinc-950 hover:underline">
            {r.name}
          </Link>
          <span className="shrink-0 text-sm text-muted">{Number(r.miles).toFixed(1)} mi</span>
        </div>
        <p className="truncate text-[13px] text-muted">
          {kind && <span className="font-medium text-link">{kind}</span>}
          {kind && r.address ? " · " : ""}
          {r.address}
        </p>
        <StatusBadge status={r.status} />
        {friends && (
          <p className="flex items-center gap-1.5 text-[13px] font-medium text-friends-ink">
            <FriendsFavoriteIcon size={13} />
            <span className="truncate">{friends}</span>
          </p>
        )}
        {r.is_want && (
          <p className="flex items-center gap-1.5 text-[13px] font-medium text-want">
            <svg viewBox="0 0 24 24" width={13} height={13} fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7" />
            </svg>
            On your Want to try list
          </p>
        )}
        {hidden && <p className="text-[13px] text-muted">You hid this place</p>}
      </div>
      <div className="flex shrink-0 items-center">
        <button
          type="button"
          onClick={userId ? onToggleStar : onLocked}
          aria-pressed={userId ? starred : undefined}
          aria-label={starred ? `Remove ${r.name} from your favorites` : `Add ${r.name} to your favorites`}
          className="flex h-11 w-11 items-center justify-center rounded-lg hover:bg-zinc-100"
        >
          <FavoriteIcon filled={starred} size={22} />
        </button>
        {userId && <AddToListMenu userId={userId} entityId={r.id} />}
        {userId && <RowMenu name={r.name} hidden={hidden} onToggleHide={onToggleHide} />}
      </div>
    </li>
  );
}
