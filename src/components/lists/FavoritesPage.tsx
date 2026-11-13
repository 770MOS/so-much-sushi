"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import PlacesBrowser from "@/components/lists/PlacesBrowser";
import JoinPanel from "@/components/lists/JoinPanel";
import { FavoriteIcon } from "@/components/icons";
import { PEOPLE_PATH, placeWord, type ListPlace } from "@/lib/lists";
import { announceMark, useMarkChanges } from "@/lib/placeMarks";
import { useUserId } from "@/lib/useSignedIn";
import { useHerePoint } from "@/lib/useHerePoint";

// The Favorites page (mocked 2026-11-12): every favorite anywhere, grouped by town, nearest to
// the viewer first, in the same list-and-map layout as search. Favorites mean "I recommend
// this": friends always see them. Taking the heart off keeps the row (with an empty heart) until
// the page is opened again, so a slip is one tap to undo.
export default function FavoritesPage() {
  const supabase = useMemo(() => createClient(), []);
  const userId = useUserId();
  const here = useHerePoint(userId);
  const [places, setPlaces] = useState<{ userId: string; rows: ListPlace[] } | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    supabase.rpc("my_favorites").then(({ data, error: err }) => {
      if (cancelled) return;
      if (err) setError("Something went wrong loading your favorites. Try again in a moment.");
      setPlaces({ userId, rows: (data as ListPlace[] | null) ?? [] });
    });
    return () => {
      cancelled = true;
    };
  }, [userId, supabase]);

  const rows = places && places.userId === userId ? places.rows : null;

  function setStarred(id: string, on: boolean) {
    setPlaces((prev) => (prev ? { ...prev, rows: prev.rows.map((p) => (p.id === id ? { ...p, is_starred: on } : p)) } : prev));
  }

  async function toggle(p: ListPlace) {
    if (!userId) return;
    const on = p.is_starred;
    const { error: err } = on
      ? await supabase.from("stars").delete().eq("user_id", userId).eq("entity_id", p.id)
      : await supabase.from("stars").insert({ user_id: userId, entity_id: p.id });
    if (err) return;
    setStarred(p.id, !on);
    announceMark({ id: p.id, starred: !on, from: "lists" });
  }

  // A heart changed in the place panel: follow it here.
  useMarkChanges((change) => {
    if (change.from === "lists" || change.starred === undefined) return;
    if (rows?.some((p) => p.id === change.id)) setStarred(change.id, change.starred);
    else if (change.starred && userId) {
      // A new favorite from the panel: load it into the page.
      supabase.rpc("my_favorites").then(({ data }) => {
        if (data) setPlaces({ userId, rows: data as ListPlace[] });
      });
    }
  });

  if (userId === undefined) return <main className="flex-1" />;
  if (userId === null) {
    return (
      <JoinPanel
        icon={<FavoriteIcon filled size={28} />}
        title="Favorites come with a free account"
        body="Heart the places you love to keep them all in one place. Your friends see your favorites, and you see theirs on the map."
      />
    );
  }

  return (
    <PlacesBrowser
      places={rows}
      here={here}
      filters
      groupByTown
      mapNoun="favorites"
      heading={(shown, sort) => {
        const towns = new Set(shown.map((p) => `${p.city}|${p.state}`).filter((t) => t !== "null|null")).size;
        return (
          <div className="flex flex-col gap-1.5 border-b border-[#f0f0f0] px-5 pb-3.5 pt-4 md:px-6">
            <h1 className="text-2xl font-medium tracking-tight text-zinc-950">Your favorites</h1>
            {rows && rows.length > 0 && (
              <p className="text-sm text-muted" aria-live="polite">
                {shown.length.toLocaleString("en-US")} {placeWord(shown.length)}
                {towns > 1 ? ` in ${towns} towns` : ""}
                {sort === "nearest" ? ", nearest to you first" : ", A–Z"}
              </p>
            )}
            <p className="mt-0.5 flex items-center gap-1.5 text-[13px] text-muted">
              <svg viewBox="0 0 24 24" width={15} height={15} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d={PEOPLE_PATH} />
              </svg>
              Your friends see your favorites.
            </p>
            {error && <p className="text-sm text-red-700">{error}</p>}
          </div>
        );
      }}
      rowEnd={(p) => (
        <button
          type="button"
          onClick={() => toggle(p)}
          aria-pressed={p.is_starred}
          aria-label={p.is_starred ? `Remove ${p.name} from your favorites` : `Add ${p.name} back to your favorites`}
          className="flex h-11 w-11 items-center justify-center rounded-lg hover:bg-zinc-100"
        >
          <FavoriteIcon filled={p.is_starred} size={22} />
        </button>
      )}
      empty={
        <div className="mx-auto flex max-w-xs flex-col items-center gap-2">
          <p className="text-[15px] text-zinc-950">No favorites yet.</p>
          <p>Tap the heart on any place to add it here.</p>
          <Link href="/" className="mt-1 font-medium text-zinc-950 underline">
            Find places
          </Link>
        </div>
      }
    />
  );
}
