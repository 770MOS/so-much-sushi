"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import Avatar from "@/components/Avatar";
import PlacesBrowser from "@/components/lists/PlacesBrowser";
import { VisibilityIcon } from "@/components/lists/VisibilityMenu";
import RelationButton from "@/components/friends/RelationButton";
import AddToListMenu from "@/components/AddToListMenu";
import Dialog, { secondaryButton } from "@/components/lists/Dialog";
import { FavoriteIcon } from "@/components/icons";
import { FLAG_PATH, placeWord, townsLine, VISIBILITY } from "@/lib/lists";
import { monthYear, plural, type PersonList, type PersonPageData, type Relation } from "@/lib/friends";
import { announceMark, useMarkChanges } from "@/lib/placeMarks";
import { useUserId } from "@/lib/useSignedIn";
import { useHerePoint } from "@/lib/useHerePoint";

// A person's page (mocked 2026-11-12). For a friend: their favorites in the list-and-map layout,
// with tabs for Favorites and the lists they share with you; places you've also favorited say so,
// and each row has a heart (add to your favorites) and Add to list. For anyone else: their name,
// how you're connected, and their public lists.

function Menu({ name, onRemove }: { name: string; onRemove: () => void }) {
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
        className="flex h-11 w-11 items-center justify-center rounded-lg text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
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
              onRemove();
            }}
            className="flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-red-700 hover:bg-zinc-100"
          >
            Remove friend
          </button>
        </div>
      )}
    </div>
  );
}

function ListRows({ lists, empty }: { lists: PersonList[]; empty: string }) {
  if (lists.length === 0) return <p className="px-5 py-8 text-sm text-muted md:px-6">{empty}</p>;
  return (
    <ul>
      {lists.map((l) => (
        <li key={l.id} className="border-b border-[#f0f0f0]">
          <Link href={`/lists/${l.id}`} className="flex items-center gap-3 px-5 py-3.5 text-zinc-950 hover:bg-zinc-50 md:px-6">
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="flex items-center gap-2 truncate text-base font-medium">
                {l.is_default && (
                  <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="#3b5bdb" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d={FLAG_PATH} />
                  </svg>
                )}
                {l.name}
              </span>
              <span className="flex items-center gap-1.5 truncate text-sm text-muted">
                <VisibilityIcon v={l.visibility} size={14} />
                {VISIBILITY[l.visibility].label} · {l.place_count} {placeWord(l.place_count)}
                {l.towns.length > 0 && ` · ${townsLine(l.towns, l.towns.length)}`}
              </span>
            </span>
            <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#707070" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M9 6l6 6l-6 6" />
            </svg>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export default function PersonView({ initial }: { initial: PersonPageData }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const userId = useUserId();
  const here = useHerePoint(userId);
  const [person, setPerson] = useState(initial);
  const [tab, setTab] = useState<"favorites" | "lists">("favorites");
  const [removing, setRemoving] = useState(false);
  const signedIn = Boolean(userId);
  const first = person.name.split(/\s+/)[0];
  const close = person.relation === "friends" || person.relation === "self";

  async function reload() {
    const { data } = await supabase.rpc("person_page", { person_handle: person.handle });
    if (data) setPerson(data as PersonPageData);
  }

  function relationChanged(r: Relation) {
    setPerson((p) => ({ ...p, relation: r }));
    // Becoming friends shows their favorites and Friends lists.
    reload();
    router.refresh();
  }

  async function toggleStar(id: string, on: boolean) {
    if (!userId) return;
    const { error } = on
      ? await supabase.from("stars").delete().eq("user_id", userId).eq("entity_id", id)
      : await supabase.from("stars").insert({ user_id: userId, entity_id: id });
    if (error) return;
    setPerson((p) => ({ ...p, favorites: p.favorites.map((f) => (f.id === id ? { ...f, is_starred: !on } : f)) }));
    announceMark({ id, starred: !on, from: "lists" });
  }
  useMarkChanges((change) => {
    if (change.from === "lists" || change.starred === undefined) return;
    const starred = change.starred;
    setPerson((p) => ({ ...p, favorites: p.favorites.map((f) => (f.id === change.id ? { ...f, is_starred: starred } : f)) }));
  });

  async function removeFriend() {
    await supabase.rpc("remove_friend", { other: person.id });
    setRemoving(false);
    relationChanged("none");
  }

  const nameBlock = (
    <div className="flex items-center gap-3.5 px-5 pt-4 md:px-6">
      <Avatar name={person.name} seed={person.handle} size={52} />
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <h1 className="truncate text-2xl font-medium tracking-tight text-zinc-950">{person.name}</h1>
        <p className="text-sm text-muted">
          {person.relation === "self"
            ? "This is how your friends see your page"
            : person.relation === "friends"
              ? person.friends_since
                ? `Friends since ${monthYear(person.friends_since)}`
                : "Friends"
              : `@${person.handle}`}
        </p>
      </div>
      {person.relation === "friends" && <Menu name={person.name} onRemove={() => setRemoving(true)} />}
    </div>
  );

  const tabs = (
    <nav aria-label={`${first}'s places`} className="flex gap-1 border-b border-line px-5 pt-3.5 md:px-6">
      {(["favorites", "lists"] as const).map((t) => (
        <button
          key={t}
          type="button"
          aria-pressed={tab === t}
          onClick={() => setTab(t)}
          className={`inline-flex h-11 items-center gap-1.5 px-2.5 text-[15px] font-medium ${
            tab === t ? "text-zinc-950 shadow-[inset_0_-2px_0_#141414]" : "text-muted hover:text-zinc-950"
          }`}
        >
          {t === "favorites" ? "Favorites" : "Lists"}
          <span className="font-normal text-[#707070]">{t === "favorites" ? person.favorites_count : person.lists.length}</span>
        </button>
      ))}
    </nav>
  );

  const backLink = signedIn && (
    <Link href="/friends" className="inline-flex h-10 shrink-0 items-center gap-1.5 text-sm font-medium text-zinc-950 hover:underline">
      <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M15 6l-6 6l6 6" />
      </svg>
      Friends
    </Link>
  );

  const removeDialog = removing && (
    <Dialog title={`Remove ${person.name}?`} onClose={() => setRemoving(false)}>
      <p className="mt-2 text-[15px] leading-relaxed text-muted">
        You’ll stop seeing each other’s favorites and Friends lists. They aren’t told; you can add each other again later.
      </p>
      <div className="mt-5 flex justify-end gap-2">
        <button type="button" onClick={() => setRemoving(false)} className={secondaryButton}>
          Keep
        </button>
        <button
          type="button"
          onClick={removeFriend}
          className="inline-flex h-11 items-center justify-center rounded-[10px] bg-red-700 px-5 text-[15px] font-medium text-white hover:bg-red-800"
        >
          Remove friend
        </button>
      </div>
    </Dialog>
  );

  // ------------------------------------------------ not friends: name, connection, public lists
  if (!close) {
    return (
      <main className="mx-auto flex w-full max-w-[720px] flex-1 flex-col gap-6 pb-14 pt-4">
        <div className="flex flex-wrap items-center justify-between gap-4 pr-5 md:pr-6">
          {nameBlock}
          <div className="pl-5 pt-4 md:pl-0">
            <RelationButton
              personId={person.id}
              name={person.name}
              relation={person.relation}
              signedIn={signedIn}
              next={`/u/${person.handle}`}
              onChange={relationChanged}
            />
          </div>
        </div>
        <p className="px-5 text-[15px] text-muted md:px-6">
          {person.relation === "sent"
            ? `You asked ${first} to be friends. Once they accept, you’ll see each other’s favorites.`
            : person.relation === "received"
              ? `${first} asked to be friends. Accept to see each other’s favorites.`
              : `Friends see each other’s favorites and lists set to Friends.`}
        </p>
        <section aria-labelledby="pub-h" className="flex flex-col">
          <h2 id="pub-h" className="border-b border-line px-5 pb-2 text-lg font-medium text-zinc-950 md:px-6">
            Public lists
          </h2>
          <ListRows lists={person.lists} empty={`${first} has no public lists.`} />
        </section>
      </main>
    );
  }

  // ------------------------------------------------ friends (or your own page): favorites and lists
  if (tab === "lists") {
    return (
      <main className="flex flex-1 flex-col">
        <div className="border-b border-line px-4 py-2.5 md:px-6">{backLink}</div>
        <div className="mx-auto w-full max-w-[720px]">
          {nameBlock}
          {tabs}
          <ListRows
            lists={person.lists}
            empty={person.relation === "self" ? "You have no lists yet." : `${first} doesn’t share any lists with you yet.`}
          />
        </div>
        {removeDialog}
      </main>
    );
  }

  return (
    <>
      <PlacesBrowser
        places={person.favorites}
        here={here}
        filters
        groupByTown
        showFriends={false}
        mapNoun="favorites"
        toolbar={backLink ? <>{backLink}<span aria-hidden="true" className="mx-1 h-6 w-px shrink-0 bg-[#dddddd]" /></> : undefined}
        heading={() => (
          <div className="border-b border-[#f0f0f0] pb-0">
            {nameBlock}
            {tabs}
          </div>
        )}
        rowNote={(p) =>
          person.relation === "friends" && p.is_starred ? (
            <p className="flex items-center gap-1.5 text-[13px] font-medium text-favorite-ink">
              <FavoriteIcon filled size={13} />
              Also your favorite
            </p>
          ) : null
        }
        rowEnd={
          userId && person.relation === "friends"
            ? (p) => (
                <>
                  <button
                    type="button"
                    onClick={() => toggleStar(p.id, p.is_starred)}
                    aria-pressed={p.is_starred}
                    aria-label={p.is_starred ? `Remove ${p.name} from your favorites` : `Add ${p.name} to your favorites`}
                    className="flex h-11 w-11 items-center justify-center rounded-lg hover:bg-zinc-100"
                  >
                    <FavoriteIcon filled={p.is_starred} size={22} />
                  </button>
                  <AddToListMenu userId={userId} entityId={p.id} />
                </>
              )
            : undefined
        }
        empty={person.relation === "self" ? "You have no favorites yet." : `${first} hasn’t favorited any places yet.`}
        footer={
          person.relation === "friends" && person.favorites.length > 0 ? (
            <p className="px-5 pb-6 pt-4 text-[13px] text-muted md:px-6">
              {first} sees your favorites the same way. {plural(person.favorites.filter((f) => f.is_starred).length, "place is", "places are")} a
              favorite of you both.
            </p>
          ) : null
        }
      />
      {removeDialog}
    </>
  );
}
