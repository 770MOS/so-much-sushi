"use client";

import { useMemo, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import Dialog, { fieldClass, primaryButton, secondaryButton } from "@/components/lists/Dialog";
import VisibilityChoice from "@/components/lists/VisibilityChoice";
import type { Visibility } from "@/lib/lists";

// New list: a name and who can see it (Just you to start, decided 2026-11-12).
export default function NewListDialog({ userId, onClose, onCreated }: { userId: string; onClose: () => void; onCreated: (id: string) => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [name, setName] = useState("");
  const [visibility, setVisibility] = useState<Visibility>("private");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create(e: FormEvent) {
    e.preventDefault();
    const n = name.trim();
    if (!n || busy) return;
    setBusy(true);
    setError(null);
    const { data, error: err } = await supabase
      .from("lists")
      .insert({ owner_id: userId, name: n, visibility })
      .select("id")
      .single();
    setBusy(false);
    if (err || !data) {
      setError("Something went wrong making the list. Try again.");
      return;
    }
    onCreated(data.id as string);
  }

  return (
    <Dialog title="New list" onClose={onClose}>
      <form onSubmit={create} className="mt-4 flex flex-col gap-4">
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-950">Name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} placeholder="Date night, Brunch spots…" className={fieldClass} />
        </label>
        <VisibilityChoice value={visibility} onChange={setVisibility} />
        {error && <p className="text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} className={secondaryButton}>
            Cancel
          </button>
          <button type="submit" disabled={!name.trim() || busy} className={primaryButton}>
            {busy ? "Making…" : "Make list"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
