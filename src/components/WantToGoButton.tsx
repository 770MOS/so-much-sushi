"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { BookmarkIcon } from "@/components/icons";

type Props = {
  userId: string | null;
  entityId: string;
};

// "Want to Go" quick-saves an entity to the signed-in user's one default
// list (lists.is_default_list) - created lazily on first use, named "Want
// to Go", private. Still a completely normal list afterward - editable/
// renameable/deletable from /lists like any other, this button just knows
// which one to read and write without asking.
export default function WantToGoButton({ userId, entityId }: Props) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  // null = not yet loaded (avoids a flash of the wrong state before the
  // membership check resolves).
  const [saved, setSaved] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadMembership() {
      if (!userId) {
        if (!cancelled) setSaved(false);
        return;
      }

      const { data: listRow } = await supabase
        .from("lists")
        .select("id")
        .eq("owner_id", userId)
        .eq("is_default_list", true)
        .maybeSingle();
      if (cancelled) return;

      if (!listRow) {
        setSaved(false);
        return;
      }

      const { data: itemRow } = await supabase
        .from("list_items")
        .select("entity_id")
        .eq("list_id", listRow.id)
        .eq("entity_id", entityId)
        .maybeSingle();
      if (!cancelled) setSaved(!!itemRow);
    }

    loadMembership();
    return () => {
      cancelled = true;
    };
  }, [userId, entityId, supabase]);

  async function getOrCreateDefaultListId(ownerId: string): Promise<string | null> {
    const { data: existing } = await supabase
      .from("lists")
      .select("id")
      .eq("owner_id", ownerId)
      .eq("is_default_list", true)
      .maybeSingle();
    if (existing) return existing.id;

    const { data: created, error: createError } = await supabase
      .from("lists")
      .insert({ owner_id: ownerId, name: "Want to Go", visibility: "private", is_default_list: true })
      .select("id")
      .single();
    if (!createError) return created.id;

    // Unique violation - another concurrent click/tab already created the
    // default list between the lookup above and this insert. Retry the
    // lookup rather than surfacing an error; any other error is a real
    // failure and shouldn't be silently retried.
    if (createError.code === "23505") {
      const { data: retry } = await supabase
        .from("lists")
        .select("id")
        .eq("owner_id", ownerId)
        .eq("is_default_list", true)
        .maybeSingle();
      return retry?.id ?? null;
    }

    return null;
  }

  async function handleClick() {
    if (!userId) {
      router.push("/sign-in");
      return;
    }
    if (busy || saved === null) return;

    setBusy(true);
    try {
      const listId = await getOrCreateDefaultListId(userId);
      if (!listId) return;

      if (saved) {
        const { error } = await supabase
          .from("list_items")
          .delete()
          .eq("list_id", listId)
          .eq("entity_id", entityId);
        if (!error) setSaved(false);
      } else {
        const { error } = await supabase
          .from("list_items")
          .insert({ list_id: listId, entity_id: entityId });
        if (!error) setSaved(true);
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={busy || saved === null}
      aria-pressed={!!saved}
      aria-label={saved ? "Remove from Want to Go" : "Want to Go"}
      className="flex items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-700 transition-colors hover:bg-zinc-100 disabled:cursor-not-allowed disabled:opacity-50 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
    >
      <BookmarkIcon filled={!!saved} />
      Want to Go
    </button>
  );
}
