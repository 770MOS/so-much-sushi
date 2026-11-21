"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import PlacesBrowser from "@/components/lists/PlacesBrowser";
import JoinPanel from "@/components/lists/JoinPanel";
import { EyeOffIcon } from "@/components/icons";
import { placeWord, type ListPlace } from "@/lib/lists";
import { announceMark, useMarkChanges } from "@/lib/placeMarks";
import { useUserId } from "@/lib/useSignedIn";
import { useHerePoint } from "@/lib/useHerePoint";

// The Hidden places page (decided 2026-11-21): every place you hid, anywhere, in the same
// list-and-map layout as Favorites, so a place hidden by mistake can be found and shown again.
// Only you see it. "Show again" keeps the row (with "Hide" to undo) until the page is opened
// again, so a slip is one tap to undo.
export default function HiddenPage() {
  const supabase = useMemo(() => createClient(), []);
  const userId = useUserId();
  const here = useHerePoint(userId);
  const [places, setPlaces] = useState<{ userId: string; rows: ListPlace[] } | null>(null);
  // Places shown again since the page opened.
  const [back, setBack] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    supabase.rpc("my_hidden").then(({ data, error: err }) => {
      if (cancelled) return;
      if (err) setError("Something went wrong loading your hidden places. Try again in a moment.");
      setPlaces({ userId, rows: (data as ListPlace[] | null) ?? [] });
    });
    return () => {
      cancelled = true;
    };
  }, [userId, supabase]);

  const rows = places && places.userId === userId ? places.rows : null;

  async function toggle(p: ListPlace) {
    if (!userId) return;
    const showing = back.has(p.id);
    const { error: err } = showing
      ? await supabase.from("hidden_entities").insert({ user_id: userId, entity_id: p.id })
      : await supabase.from("hidden_entities").delete().eq("user_id", userId).eq("entity_id", p.id);
    if (err) {
      setError("That didn’t save. Try again in a moment.");
      return;
    }
    setError(null);
    setShown(p.id, !showing);
    announceMark({ id: p.id, hidden: showing, from: "lists" });
  }

  function setShown(id: string, shown: boolean) {
    setBack((prev) => {
      const next = new Set(prev);
      if (shown) next.add(id);
      else next.delete(id);
      return next;
    });
  }

  // Shown again or hidden from the place panel: follow it here.
  useMarkChanges((change) => {
    if (change.from === "lists" || change.hidden === undefined) return;
    if (rows?.some((p) => p.id === change.id)) setShown(change.id, !change.hidden);
  });

  if (userId === undefined) return <main className="flex-1" />;
  if (userId === null) {
    return (
      <JoinPanel
        icon={<EyeOffIcon size={28} />}
        title="Hiding places comes with a free account"
        body="Hide the places you don’t want in your results, and bring any of them back whenever you like. Only you see what you’ve hidden."
      />
    );
  }

  return (
    <PlacesBrowser
      places={rows}
      here={here}
      filters
      groupByTown
      showFriends={false}
      mapNoun="hidden places"
      heading={(shown, sort) => {
        const towns = new Set(shown.map((p) => `${p.city}|${p.state}`).filter((t) => t !== "null|null")).size;
        return (
          <div className="flex flex-col gap-1.5 border-b border-[#f0f0f0] px-5 pb-3.5 pt-4 md:px-6">
            <h1 className="text-2xl font-medium tracking-tight text-zinc-950">Hidden places</h1>
            {rows && rows.length > 0 && (
              <p className="text-sm text-muted" aria-live="polite">
                {shown.length.toLocaleString("en-US")} {placeWord(shown.length)}
                {towns > 1 ? ` in ${towns} towns` : ""}
                {sort === "nearest" ? ", nearest to you first" : ", A–Z"}
              </p>
            )}
            <p className="mt-0.5 flex items-center gap-1.5 text-[13px] text-muted">
              <EyeOffIcon size={15} />
              Left out of your search results. Only you see these.
            </p>
            {error && <p className="text-sm text-red-700">{error}</p>}
          </div>
        );
      }}
      rowNote={(p) => (back.has(p.id) ? <p className="text-[13px] text-muted">Back in your results</p> : null)}
      rowEnd={(p) => {
        const showing = back.has(p.id);
        return (
          <button
            type="button"
            onClick={() => toggle(p)}
            aria-label={showing ? `Hide ${p.name} from your results again` : `Show ${p.name} in your results again`}
            className="inline-flex h-10 shrink-0 items-center whitespace-nowrap rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50"
          >
            {showing ? "Hide" : "Show again"}
          </button>
        );
      }}
      empty={
        <div className="mx-auto flex max-w-xs flex-col items-center gap-2">
          <p className="text-[15px] text-zinc-950">No hidden places.</p>
          <p>To leave a place out of your results, tap the eye on its row, then Hide.</p>
          <Link href="/" className="mt-1 font-medium text-zinc-950 underline">
            Find places
          </Link>
        </div>
      }
    />
  );
}
