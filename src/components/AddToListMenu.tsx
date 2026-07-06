"use client";

import { useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type ListOption = { id: string; name: string };

type Props = {
  userId: string;
  entityId: string;
};

function PlusIcon() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 5v14M5 12h14" />
    </svg>
  );
}

export default function AddToListMenu({ userId, entityId }: Props) {
  const supabase = useMemo(() => createClient(), []);
  const [open, setOpen] = useState(false);
  const [lists, setLists] = useState<ListOption[] | null>(null);
  const [membership, setMembership] = useState<Set<string>>(new Set());
  const [newListName, setNewListName] = useState("");
  const [creating, setCreating] = useState(false);

  async function loadListsAndMembership() {
    const { data: listRows } = await supabase
      .from("lists")
      .select("id, name")
      .eq("owner_id", userId)
      .order("created_at", { ascending: false });
    const myLists = listRows ?? [];
    setLists(myLists);

    const myListIds = new Set(myLists.map((l) => l.id));
    const { data: itemRows } = await supabase
      .from("list_items")
      .select("list_id")
      .eq("entity_id", entityId);
    const member = new Set(
      (itemRows ?? []).map((r) => r.list_id).filter((id) => myListIds.has(id))
    );
    setMembership(member);
  }

  async function handleToggle() {
    const next = !open;
    setOpen(next);
    if (next && lists === null) {
      await loadListsAndMembership();
    }
  }

  async function toggleMembership(listId: string) {
    if (membership.has(listId)) {
      const { error } = await supabase
        .from("list_items")
        .delete()
        .eq("list_id", listId)
        .eq("entity_id", entityId);
      if (!error) {
        setMembership((prev) => {
          const next = new Set(prev);
          next.delete(listId);
          return next;
        });
      }
    } else {
      const { error } = await supabase
        .from("list_items")
        .insert({ list_id: listId, entity_id: entityId });
      if (!error) {
        setMembership((prev) => new Set(prev).add(listId));
      }
    }
  }

  async function handleCreateList() {
    if (!newListName.trim() || creating) return;
    setCreating(true);
    const { data, error } = await supabase
      .from("lists")
      .insert({ owner_id: userId, name: newListName.trim(), visibility: "private" })
      .select("id, name")
      .single();

    if (!error && data) {
      await supabase.from("list_items").insert({ list_id: data.id, entity_id: entityId });
      setLists((prev) => [data, ...(prev ?? [])]);
      setMembership((prev) => new Set(prev).add(data.id));
      setNewListName("");
    }
    setCreating(false);
  }

  return (
    <div className="relative">
      <button
        type="button"
        onClick={handleToggle}
        aria-label="Add to list"
        aria-expanded={open}
        className="rounded p-1 text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-800 dark:hover:text-zinc-300"
      >
        <PlusIcon />
      </button>

      {open && (
        <div className="absolute right-0 z-10 mt-1 w-56 rounded-lg border border-zinc-300 bg-white p-2 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
          {lists === null ? (
            <p className="px-2 py-1 text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
          ) : lists.length === 0 ? (
            <p className="px-2 py-1 text-sm text-zinc-500 dark:text-zinc-400">No lists yet.</p>
          ) : (
            <ul className="flex flex-col">
              {lists.map((l) => (
                <li key={l.id}>
                  <button
                    type="button"
                    onClick={() => toggleMembership(l.id)}
                    aria-pressed={membership.has(l.id)}
                    className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-zinc-100 dark:hover:bg-zinc-800"
                  >
                    <span
                      className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border ${
                        membership.has(l.id)
                          ? "border-zinc-900 bg-zinc-900 dark:border-zinc-100 dark:bg-zinc-100"
                          : "border-zinc-400 dark:border-zinc-600"
                      }`}
                    >
                      {membership.has(l.id) && (
                        <span className="text-[10px] leading-none text-white dark:text-zinc-900">
                          ✓
                        </span>
                      )}
                    </span>
                    <span className="text-zinc-950 dark:text-zinc-50">{l.name}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          <div className="mt-2 flex items-center gap-1 border-t border-zinc-200 pt-2 dark:border-zinc-800">
            <input
              type="text"
              placeholder="New list name"
              value={newListName}
              onChange={(e) => setNewListName(e.target.value)}
              className="min-w-0 flex-1 rounded border border-zinc-300 bg-white px-2 py-1 text-sm text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-1 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
            />
            <button
              type="button"
              onClick={handleCreateList}
              disabled={!newListName.trim() || creating}
              className="shrink-0 rounded px-2 py-1 text-sm text-zinc-600 hover:text-zinc-900 disabled:cursor-not-allowed disabled:opacity-50 dark:text-zinc-400 dark:hover:text-zinc-100"
            >
              Add
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
