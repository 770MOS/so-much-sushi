"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import StatusBadge from "@/components/StatusBadge";
import { isNonActive } from "@/lib/entityStatus";

type ListMeta = {
  id: string;
  name: string;
  description: string | null;
  visibility: "private" | "friends" | "public";
  owner_id: string;
  owner_name: string | null;
  is_owner: boolean;
};

type ListItem = {
  entity_id: string;
  name: string;
  address: string;
  city: string | null;
  state: string | null;
  lat: number;
  lng: number;
  added_at: string;
  status: string;
};

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

const selectClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-950 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

export default function ListDetail() {
  const params = useParams<{ id: string }>();
  const listId = params.id;
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [meta, setMeta] = useState<ListMeta | null | undefined>(undefined);
  const [items, setItems] = useState<ListItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [editing, setEditing] = useState(false);
  const [editName, setEditName] = useState("");
  const [editDescription, setEditDescription] = useState("");
  const [editVisibility, setEditVisibility] = useState<"private" | "friends" | "public">(
    "private"
  );
  const [saving, setSaving] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (user === null) {
      router.replace("/sign-in");
    }
  }, [user, router]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;

    async function load() {
      const { data: metaRows, error: metaError } = await supabase.rpc("get_list_meta", {
        p_list_id: listId,
      });
      if (cancelled) return;
      if (metaError) {
        setError("Something went wrong loading this list.");
        return;
      }
      if (!metaRows || metaRows.length === 0) {
        setMeta(null);
        return;
      }
      setMeta(metaRows[0]);

      const { data: itemRows, error: itemsError } = await supabase.rpc("get_list_entities", {
        p_list_id: listId,
      });
      if (cancelled) return;
      if (itemsError) {
        setError("Something went wrong loading this list's places.");
        return;
      }
      setItems(itemRows ?? []);
    }

    load();
    return () => {
      cancelled = true;
    };
  }, [user, supabase, listId]);

  async function handleRemoveItem(entityId: string) {
    const { error: deleteError } = await supabase
      .from("list_items")
      .delete()
      .eq("list_id", listId)
      .eq("entity_id", entityId);
    if (!deleteError) {
      setItems((prev) => (prev ? prev.filter((i) => i.entity_id !== entityId) : prev));
    }
  }

  function startEditing() {
    if (!meta) return;
    setEditName(meta.name);
    setEditDescription(meta.description ?? "");
    setEditVisibility(meta.visibility);
    setEditing(true);
  }

  async function handleSaveEdit(e: FormEvent) {
    e.preventDefault();
    if (!editName.trim() || saving) return;

    setSaving(true);
    const { error: updateError } = await supabase
      .from("lists")
      .update({
        name: editName.trim(),
        description: editDescription.trim() || null,
        visibility: editVisibility,
      })
      .eq("id", listId);
    setSaving(false);

    if (!updateError) {
      setMeta((prev) =>
        prev
          ? {
              ...prev,
              name: editName.trim(),
              description: editDescription.trim() || null,
              visibility: editVisibility,
            }
          : prev
      );
      setEditing(false);
    }
  }

  async function handleDeleteList() {
    const { error: deleteError } = await supabase.from("lists").delete().eq("id", listId);
    if (!deleteError) {
      router.push("/profile");
    }
  }

  if (user === undefined || meta === undefined) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-zinc-50 px-6 dark:bg-black">
        {error ? (
          <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
        ) : (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
        )}
      </main>
    );
  }

  if (meta === null) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-zinc-50 px-6 text-center dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          This list doesn&apos;t exist or you don&apos;t have access to it.{" "}
          <Link href="/profile" className="underline">
            Back to your profile
          </Link>
          .
        </p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-zinc-50 px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-8">
        {editing ? (
          <form onSubmit={handleSaveEdit} className="flex flex-col gap-3">
            <input
              type="text"
              placeholder="List name"
              value={editName}
              onChange={(e) => setEditName(e.target.value)}
              className={inputClass}
              aria-label="Edit list name"
            />
            <input
              type="text"
              placeholder="Description (optional)"
              value={editDescription}
              onChange={(e) => setEditDescription(e.target.value)}
              className={inputClass}
              aria-label="Edit list description"
            />
            <select
              value={editVisibility}
              onChange={(e) =>
                setEditVisibility(e.target.value as "private" | "friends" | "public")
              }
              className={selectClass}
              aria-label="Edit visibility"
            >
              <option value="private">Private</option>
              <option value="friends">Friends</option>
              <option value="public">Public</option>
            </select>
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={!editName.trim() || saving}
                className="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
              >
                {saving ? "Saving…" : "Save"}
              </button>
              <button
                type="button"
                onClick={() => setEditing(false)}
                className="rounded-lg border border-zinc-300 px-4 py-2 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
              >
                Cancel
              </button>
            </div>
          </form>
        ) : (
          <div className="flex items-start justify-between gap-4">
            <div className="flex flex-col gap-2">
              <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">
                {meta.name}
              </h1>
              {meta.description && (
                <p className="text-zinc-600 dark:text-zinc-400">{meta.description}</p>
              )}
              <p className="text-sm text-zinc-500 dark:text-zinc-400">
                {meta.visibility}
                {!meta.is_owner && meta.owner_name && <> · by {meta.owner_name}</>}
              </p>
              {meta.is_owner && (
                <button
                  type="button"
                  onClick={startEditing}
                  className="self-start text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                >
                  Edit
                </button>
              )}
            </div>
            <Link
              href="/profile"
              className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
            >
              Back to profile
            </Link>
          </div>
        )}

        {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

        {items === null ? (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
        ) : items.length === 0 ? (
          <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            No places in this list yet.
          </p>
        ) : (
          <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
            {items.map((item) => (
              <li
                key={item.entity_id}
                className={`flex items-center justify-between gap-4 py-3 ${
                  isNonActive(item.status) ? "opacity-60" : ""
                }`}
              >
                <div className="flex flex-col gap-0.5">
                  <span className="font-medium text-zinc-950 dark:text-zinc-50">
                    {item.name}
                  </span>
                  <span className="text-sm text-zinc-500 dark:text-zinc-400">
                    {item.address}
                  </span>
                  <StatusBadge status={item.status} />
                </div>
                {meta.is_owner && (
                  <button
                    type="button"
                    onClick={() => handleRemoveItem(item.entity_id)}
                    className="shrink-0 text-sm text-zinc-500 underline hover:text-red-600 dark:text-zinc-400 dark:hover:text-red-400"
                  >
                    Remove
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}

        {meta.is_owner && (
          <div className="flex items-center gap-3">
            {confirmingDelete ? (
              <>
                <span className="text-sm text-zinc-600 dark:text-zinc-400">
                  Delete this list? This can&apos;t be undone.
                </span>
                <button
                  type="button"
                  onClick={handleDeleteList}
                  className="text-sm font-medium text-red-600 underline hover:text-red-700 dark:text-red-400 dark:hover:text-red-300"
                >
                  Yes, delete
                </button>
                <button
                  type="button"
                  onClick={() => setConfirmingDelete(false)}
                  className="text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
                >
                  Cancel
                </button>
              </>
            ) : (
              <button
                type="button"
                onClick={() => setConfirmingDelete(true)}
                className="self-start text-sm text-zinc-500 underline hover:text-red-600 dark:text-zinc-400 dark:hover:text-red-400"
              >
                Delete this list
              </button>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
