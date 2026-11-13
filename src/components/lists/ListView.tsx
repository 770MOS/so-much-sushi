"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import PlacesBrowser from "@/components/lists/PlacesBrowser";
import VisibilityMenu, { VisibilityIcon } from "@/components/lists/VisibilityMenu";
import EditListDialog from "@/components/lists/EditListDialog";
import AddPlacesDialog from "@/components/lists/AddPlacesDialog";
import ShareButton from "@/components/ShareButton";
import { FLAG_PATH, placeWord, townsLine, VISIBILITY, type ListPageData, type ListPlace, type Visibility } from "@/lib/lists";
import { useMarkChanges } from "@/lib/placeMarks";
import { placeIdFromPath } from "@/lib/placePanel";
import { useUserId } from "@/lib/useSignedIn";
import { useHerePoint } from "@/lib/useHerePoint";

// One list (mocked 2026-11-12) in the list-and-map layout: hearts on places that are also the
// viewer's favorites, friends' names, and for the owner Add places, who can see it (one tap),
// Share, Edit, and a menu on each place to move it to another list or take it off this one.

const barButton =
  "inline-flex h-10 shrink-0 items-center gap-1.5 rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50";

function RowMenu({
  place,
  listId,
  userId,
  onMoved,
  onRemoved,
}: {
  place: ListPlace;
  listId: string;
  userId: string;
  onMoved: (to: string) => void;
  onRemoved: () => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [open, setOpen] = useState(false);
  const [moving, setMoving] = useState(false);
  const [lists, setLists] = useState<{ id: string; name: string; is_default_list: boolean }[] | null>(null);
  const [busy, setBusy] = useState(false);
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

  async function showLists() {
    setMoving(true);
    if (lists) return;
    const { data } = await supabase.from("lists").select("id, name, is_default_list").eq("owner_id", userId).neq("id", listId);
    setLists(
      ((data ?? []) as { id: string; name: string; is_default_list: boolean }[]).sort((a, b) =>
        a.is_default_list !== b.is_default_list ? (a.is_default_list ? -1 : 1) : a.name.localeCompare(b.name)
      )
    );
  }

  async function moveTo(to: string) {
    if (busy) return;
    setBusy(true);
    // Onto the other list (fine if it's there already), then off this one.
    const { error } = await supabase.from("list_items").upsert({ list_id: to, entity_id: place.id }, { onConflict: "list_id,entity_id", ignoreDuplicates: true });
    if (!error) {
      const { error: err2 } = await supabase.from("list_items").delete().eq("list_id", listId).eq("entity_id", place.id);
      if (!err2) {
        setOpen(false);
        onMoved(to);
      }
    }
    setBusy(false);
  }

  async function remove() {
    if (busy) return;
    setBusy(true);
    const { error } = await supabase.from("list_items").delete().eq("list_id", listId).eq("entity_id", place.id);
    setBusy(false);
    if (!error) {
      setOpen(false);
      onRemoved();
    }
  }

  const item = "flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-zinc-950 hover:bg-zinc-100 disabled:opacity-50";
  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        aria-label={`More for ${place.name}: move or remove`}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => {
          setOpen((o) => !o);
          setMoving(false);
        }}
        className="flex h-11 w-11 items-center justify-center rounded-lg text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900"
      >
        <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" aria-hidden="true">
          <path d="M5 12h.01M12 12h.01M19 12h.01" />
        </svg>
      </button>
      {open && (
        <div role="menu" className="absolute right-0 z-20 mt-1 max-h-80 w-64 overflow-y-auto rounded-xl border border-line bg-white p-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]">
          {!moving ? (
            <>
              <button type="button" role="menuitem" onClick={showLists} className={item}>
                Move to another list…
              </button>
              <button type="button" role="menuitem" onClick={remove} disabled={busy} className={item}>
                Remove from this list
              </button>
            </>
          ) : lists === null ? (
            <p className="px-3 py-2.5 text-sm text-muted">Loading your lists…</p>
          ) : lists.length === 0 ? (
            <p className="px-3 py-2.5 text-sm text-muted">You have no other lists yet.</p>
          ) : (
            <>
              <p className="px-3 pb-1 pt-2 text-[13px] text-muted">Move to</p>
              {lists.map((l) => (
                <button key={l.id} type="button" role="menuitem" onClick={() => moveTo(l.id)} disabled={busy} className={item}>
                  <span className="truncate">{l.name}</span>
                </button>
              ))}
            </>
          )}
        </div>
      )}
    </div>
  );
}

export default function ListView({ initial }: { initial: ListPageData }) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const pathname = usePathname();
  const userId = useUserId();
  const here = useHerePoint(userId);
  const [list, setList] = useState<ListPageData>(initial);
  const [editing, setEditing] = useState(false);
  const [adding, setAdding] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  const reload = useCallback(async () => {
    const { data } = await supabase.rpc("list_page", { list_id: initial.id });
    if (data && !("hidden" in data)) setList(data as ListPageData);
  }, [supabase, initial.id]);

  // Signing in or out in another tab, or the panel changing marks: ask again.
  const lastUser = useRef(userId);
  useEffect(() => {
    if (userId === undefined || lastUser.current === userId) return;
    lastUser.current = userId;
    reload();
  }, [userId, reload]);
  useMarkChanges((change) => {
    if (change.from === "lists") return;
    if (list.places.some((p) => p.id === change.id) || (list.is_default && change.want !== undefined)) reload();
  });
  // Closing a place panel: its Add to list may have changed this list.
  const selectedId = placeIdFromPath(pathname);
  const hadPanel = useRef(false);
  useEffect(() => {
    if (selectedId) hadPanel.current = true;
    else if (hadPanel.current) {
      hadPanel.current = false;
      reload();
    }
  }, [selectedId, reload]);

  async function changeVisibility(v: Visibility) {
    const { error } = await supabase.from("lists").update({ visibility: v }).eq("id", list.id);
    if (error) return false;
    setList((l) => ({ ...l, visibility: v }));
    return true;
  }

  const owner = list.is_owner;
  const signedIn = Boolean(userId);
  const near = useMemo(
    () => (here ? { lat: here.lat, lng: here.lng, label: here.label } : list.places[0] ? { lat: list.places[0].lat, lng: list.places[0].lng } : null),
    [here, list.places]
  );
  const towns = useMemo(() => {
    const counts = new Map<string, number>();
    for (const p of list.places) if (p.city) counts.set(p.city, (counts.get(p.city) ?? 0) + 1);
    const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([c]) => c);
    return { top: sorted.slice(0, 3), total: sorted.length };
  }, [list.places]);
  const placeIds = useMemo(() => new Set(list.places.map((p) => p.id)), [list.places]);

  const toolbar = (
    <>
      {signedIn && (
        <Link href="/lists" className="inline-flex h-10 shrink-0 items-center gap-1.5 text-sm font-medium text-zinc-950 hover:underline">
          <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M15 6l-6 6l6 6" />
          </svg>
          {owner ? "Your lists" : "Lists"}
        </Link>
      )}
      {signedIn && <span aria-hidden="true" className="mx-1 h-6 w-px shrink-0 bg-[#dddddd]" />}
      {owner && (
        <button
          type="button"
          onClick={() => setAdding(true)}
          className="inline-flex h-10 shrink-0 items-center gap-1.5 rounded-[10px] bg-primary px-3.5 text-sm font-medium text-white hover:bg-primary-hover"
        >
          <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
            <path d="M12 5v14M5 12h14" />
          </svg>
          Add places
        </button>
      )}
      <span className="shrink-0" onClickCapture={() => setNote(owner && list.visibility === "private" ? "Only you can open this link. To share it, change who can see the list to Friends or Public." : null)}>
        <ShareButton path={`/lists/${list.id}`} title={`${list.name} — a list on So Much Sushi`} />
      </span>
      {owner && !list.is_default && (
        <button type="button" onClick={() => setEditing(true)} className={barButton}>
          <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M4 20h4l10.5 -10.5a2.828 2.828 0 1 0 -4 -4l-10.5 10.5v4M13.5 6.5l4 4" />
          </svg>
          Edit
        </button>
      )}
    </>
  );

  return (
    <>
      <PlacesBrowser
        places={list.places}
        here={here}
        heartBadge={signedIn}
        mapNoun="places"
        toolbar={toolbar}
        heading={(shown, sort) => (
          <div className="flex flex-col gap-1.5 border-b border-[#f0f0f0] px-5 pb-3.5 pt-4 md:px-6">
            <h1 className="flex items-center gap-2 text-[26px] font-medium tracking-tight text-zinc-950">
              {list.is_default && (
                <svg viewBox="0 0 24 24" width={22} height={22} fill="none" stroke="#3b5bdb" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d={FLAG_PATH} />
                </svg>
              )}
              {list.name}
            </h1>
            {list.description && <p className="text-[15px] text-zinc-700">{list.description}</p>}
            <p className="text-sm text-muted" aria-live="polite">
              {shown.length} {placeWord(shown.length)}
              {towns.top.length > 0 && ` · ${townsLine(towns.top, towns.total)}`}
              {shown.length > 1 && (sort === "nearest" ? " · nearest to you first" : " · A–Z")}
            </p>
            <div className="mt-1 flex flex-wrap items-center gap-2 text-[13px] text-muted">
              {owner ? (
                <VisibilityMenu value={list.visibility} onChange={changeVisibility} />
              ) : (
                <span className="inline-flex items-center gap-1.5">
                  <VisibilityIcon v={list.visibility} />
                  <span>
                    {list.visibility === "public" ? "Public list" : list.visibility === "friends" ? "Shared with friends" : VISIBILITY.private.label}
                    {" by "}
                    {list.owner.handle && signedIn ? (
                      <Link href={`/u/${list.owner.handle}`} className="font-medium text-zinc-950 hover:underline">
                        {list.owner.name}
                      </Link>
                    ) : (
                      <span className="font-medium text-zinc-950">{list.owner.name}</span>
                    )}
                  </span>
                </span>
              )}
            </div>
            {note && (
              <p role="status" className="text-[13px] text-muted">
                {note}
              </p>
            )}
          </div>
        )}
        rowEnd={owner && userId ? (p) => (
          <RowMenu
            place={p}
            listId={list.id}
            userId={userId}
            onMoved={() => setList((l) => ({ ...l, places: l.places.filter((x) => x.id !== p.id) }))}
            onRemoved={() => setList((l) => ({ ...l, places: l.places.filter((x) => x.id !== p.id) }))}
          />
        ) : undefined}
        empty={
          owner ? (
            <div className="mx-auto flex max-w-xs flex-col items-center gap-2">
              <p className="text-[15px] text-zinc-950">No places yet.</p>
              <p>Add places by name, or use Add to list on any place.</p>
              <button type="button" onClick={() => setAdding(true)} className="mt-1 font-medium text-zinc-950 underline">
                Add places
              </button>
            </div>
          ) : (
            "No places on this list yet."
          )
        }
        footer={
          signedIn && list.places.length > 0 ? (
            <p className="px-5 py-4 text-[13px] text-muted md:px-6">
              Hearts mark places that are also your favorites. Adding a place to a list never makes it a favorite.
            </p>
          ) : !signedIn ? (
            <p className="px-5 py-4 text-[13px] text-muted md:px-6">
              <Link href="/sign-up" className="font-medium text-zinc-950 underline">
                Join free
              </Link>{" "}
              to make your own lists and keep your favorites.
            </p>
          ) : null
        }
      />
      {editing && (
        <EditListDialog
          listId={list.id}
          values={{ name: list.name, description: list.description, visibility: list.visibility }}
          onClose={() => setEditing(false)}
          onSaved={(v) => {
            setList((l) => ({ ...l, ...v }));
            setEditing(false);
            router.refresh();
          }}
          onDeleted={() => router.push("/lists")}
        />
      )}
      {adding && (
        <AddPlacesDialog
          listId={list.id}
          listName={list.name}
          near={near}
          onList={placeIds}
          onClose={(changed) => {
            setAdding(false);
            if (changed) reload();
          }}
        />
      )}
    </>
  );
}
