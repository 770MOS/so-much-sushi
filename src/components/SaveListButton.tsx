"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Props = {
  userId: string;
  listId: string;
  initiallySaved: boolean;
  onChange?: (saved: boolean) => void;
};

export default function SaveListButton({ userId, listId, initiallySaved, onChange }: Props) {
  const [saved, setSaved] = useState(initiallySaved);
  const [pending, setPending] = useState(false);

  async function toggle() {
    if (pending) return;
    setPending(true);
    const supabase = createClient();

    if (saved) {
      const { error } = await supabase
        .from("saved_lists")
        .delete()
        .eq("user_id", userId)
        .eq("list_id", listId);
      if (!error) {
        setSaved(false);
        onChange?.(false);
      }
    } else {
      const { error } = await supabase.from("saved_lists").insert({ user_id: userId, list_id: listId });
      if (!error) {
        setSaved(true);
        onChange?.(true);
      }
    }
    setPending(false);
  }

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={pending}
      aria-pressed={saved}
      className={`shrink-0 rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${
        saved
          ? "border-primary bg-primary text-white"
          : "border-zinc-300 text-zinc-600 hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
      }`}
    >
      {saved ? "Saved" : "Save"}
    </button>
  );
}
