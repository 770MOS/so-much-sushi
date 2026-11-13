"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { announceMark } from "@/lib/placeMarks";

type ListRow = { id: string; name: string; is_default_list: boolean };

type Props = {
  userId: string;
  placeId: string;
  // After a change: whether it's on Want to try, and the other lists it's on (A-Z).
  onChange: (want: boolean, lists: { id: string; name: string }[]) => void;
};

const FLAG_PATH = "M5 5a5 5 0 0 1 7 0a5 5 0 0 0 7 0v9a5 5 0 0 1 -7 0a5 5 0 0 0 -7 0v-9zM5 21v-7";

// The place panel's "Add to list" (decided 2026-11-10): the ready-made Want to try list first,
// then the person's own lists A-Z, then New list. Each list is a tick box.
export default function ListButton({ userId, placeId, onChange }: Props) {
  const supabase = useMemo(() => createClient(), []);
  const [open, setOpen] = useState(false);
  const [lists, setLists] = useState<ListRow[] | null>(null);
  const [member, setMember] = useState<Set<string>>(new Set());
  const [naming, setNaming] = useState(false);
  const [newName, setNewName] = useState("");
  const [busy, setBusy] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);

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

  async function load() {
    const { data } = await supabase.from("lists").select("id, name, is_default_list").eq("owner_id", userId);
    const rows = ((data ?? []) as ListRow[]).sort((a, b) =>
      a.is_default_list !== b.is_default_list ? (a.is_default_list ? -1 : 1) : a.name.localeCompare(b.name)
    );
    setLists(rows);
    const ids = rows.map((l) => l.id);
    const { data: items } = ids.length
      ? await supabase.from("list_items").select("list_id").eq("entity_id", placeId).in("list_id", ids)
      : { data: [] };
    setMember(new Set((items ?? []).map((i: { list_id: string }) => i.list_id)));
  }

  function report(rows: ListRow[], next: Set<string>) {
    const want = rows.some((l) => l.is_default_list && next.has(l.id));
    onChange(
      want,
      rows.filter((l) => !l.is_default_list && next.has(l.id)).map((l) => ({ id: l.id, name: l.name }))
    );
  }

  async function toggle(list: ListRow) {
    if (busy || !lists) return;
    setBusy(true);
    const on = member.has(list.id);
    const { error } = on
      ? await supabase.from("list_items").delete().eq("list_id", list.id).eq("entity_id", placeId)
      : await supabase.from("list_items").insert({ list_id: list.id, entity_id: placeId });
    setBusy(false);
    if (error) return;
    const next = new Set(member);
    if (on) next.delete(list.id);
    else next.add(list.id);
    setMember(next);
    report(lists, next);
    if (list.is_default_list) announceMark({ id: placeId, want: !on, from: "panel" });
  }

  async function create() {
    const name = newName.trim();
    if (!name || busy || !lists) return;
    setBusy(true);
    const { data, error } = await supabase
      .from("lists")
      .insert({ owner_id: userId, name })
      .select("id, name, is_default_list")
      .single();
    if (!error && data) {
      await supabase.from("list_items").insert({ list_id: data.id, entity_id: placeId });
      const rows = [...lists, data as ListRow].sort((a, b) =>
        a.is_default_list !== b.is_default_list ? (a.is_default_list ? -1 : 1) : a.name.localeCompare(b.name)
      );
      const next = new Set(member).add(data.id);
      setLists(rows);
      setMember(next);
      report(rows, next);
      setNewName("");
      setNaming(false);
    }
    setBusy(false);
  }

  return (
    <span ref={ref} className="relative inline-flex">
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="true"
        onClick={() => {
          const next = !open;
          setOpen(next);
          if (next && lists === null) load();
        }}
        className="inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border border-zinc-950 bg-white pl-3.5 pr-3 text-sm font-medium text-zinc-950 hover:bg-zinc-50"
      >
        <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M19 8h-14M5 12h9M11 16h-6M15 16h6M18 13v6" />
        </svg>
        Add to list
        <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d={open ? "M6 15l6 -6l6 6" : "M6 9l6 6l6 -6"} />
        </svg>
      </button>
      {open && (
        <div className="absolute left-0 top-[50px] z-30 w-[260px] rounded-xl border border-line bg-white p-1.5 shadow-[0_12px_30px_rgba(0,0,0,0.12)]">
          {lists === null ? (
            <p className="px-2.5 py-2 text-sm text-muted">Loading…</p>
          ) : (
            lists.map((l) => (
              <label key={l.id} className="flex min-h-11 cursor-pointer items-center gap-2.5 rounded-lg px-2.5 text-[15px] text-zinc-950 hover:bg-zinc-50">
                <input
                  type="checkbox"
                  checked={member.has(l.id)}
                  onChange={() => toggle(l)}
                  disabled={busy}
                  className="m-0 h-[18px] w-[18px] accent-zinc-950"
                />
                {l.is_default_list && (
                  <svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="#3b5bdb" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d={FLAG_PATH} />
                  </svg>
                )}
                <span className="min-w-0 truncate">{l.name}</span>
                {l.is_default_list && <span className="ml-auto text-xs text-[#707070]">Ready-made</span>}
              </label>
            ))
          )}
          {naming ? (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                create();
              }}
              className="mt-1 flex items-center gap-1.5 border-t border-[#f0f0f0] px-1 pt-1.5"
            >
              <label htmlFor="new-list-name" className="sr-only">
                New list name
              </label>
              <input
                id="new-list-name"
                autoFocus
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="List name"
                maxLength={80}
                className="h-10 min-w-0 flex-1 rounded-lg border border-line px-2.5 text-[15px] focus:border-zinc-950 focus:outline-none"
              />
              <button type="submit" disabled={busy || !newName.trim()} className="h-10 rounded-lg bg-primary px-3 text-sm font-medium text-white disabled:opacity-50">
                Add
              </button>
            </form>
          ) : (
            <button
              type="button"
              onClick={() => setNaming(true)}
              disabled={lists === null}
              className="mt-1 flex min-h-11 w-full items-center gap-2.5 border-t border-[#f0f0f0] px-2.5 text-left text-[15px] font-medium text-link"
            >
              <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
                <path d="M12 5v14M5 12h14" />
              </svg>
              New list
            </button>
          )}
        </div>
      )}
    </span>
  );
}
