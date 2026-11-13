"use client";

import { useMemo, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import Dialog, { fieldClass, primaryButton, secondaryButton } from "@/components/lists/Dialog";
import VisibilityChoice from "@/components/lists/VisibilityChoice";
import type { Visibility } from "@/lib/lists";

type Values = { name: string; description: string | null; visibility: Visibility };

// Edit a list: its name, a line about it, who can see it, or delete it. (Want to try keeps its
// name and can't be deleted; it isn't edited here.)
export default function EditListDialog({
  listId,
  values,
  onClose,
  onSaved,
  onDeleted,
}: {
  listId: string;
  values: Values;
  onClose: () => void;
  onSaved: (v: Values) => void;
  onDeleted: () => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [name, setName] = useState(values.name);
  const [description, setDescription] = useState(values.description ?? "");
  const [visibility, setVisibility] = useState<Visibility>(values.visibility);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(e: FormEvent) {
    e.preventDefault();
    const next = { name: name.trim(), description: description.trim() || null, visibility };
    if (!next.name || busy) return;
    setBusy(true);
    setError(null);
    const { error: err } = await supabase.from("lists").update(next).eq("id", listId);
    setBusy(false);
    if (err) {
      setError("Something went wrong saving the list. Try again.");
      return;
    }
    onSaved(next);
  }

  async function remove() {
    setBusy(true);
    setError(null);
    const { error: err, count } = await supabase.from("lists").delete({ count: "exact" }).eq("id", listId);
    setBusy(false);
    if (err || count === 0) {
      setError("Something went wrong deleting the list. Try again.");
      return;
    }
    onDeleted();
  }

  if (confirming) {
    return (
      <Dialog title={`Delete “${values.name}”?`} onClose={onClose}>
        <p className="mt-2 text-[15px] leading-relaxed text-muted">
          The list goes for good. Its places stay on the map, and any you favorited stay in your favorites.
        </p>
        {error && <p className="mt-3 text-sm text-red-700">{error}</p>}
        <div className="mt-5 flex justify-end gap-2">
          <button type="button" onClick={() => setConfirming(false)} className={secondaryButton}>
            Keep it
          </button>
          <button
            type="button"
            onClick={remove}
            disabled={busy}
            className="inline-flex h-11 items-center justify-center rounded-[10px] bg-red-700 px-5 text-[15px] font-medium text-white hover:bg-red-800 disabled:opacity-50"
          >
            {busy ? "Deleting…" : "Delete list"}
          </button>
        </div>
      </Dialog>
    );
  }

  return (
    <Dialog title="Edit list" onClose={onClose}>
      <form onSubmit={save} className="mt-4 flex flex-col gap-4">
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-950">Name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} className={fieldClass} />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-950">
            About this list <span className="font-normal text-muted">(optional)</span>
          </span>
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} maxLength={300} rows={2} className={fieldClass} />
        </label>
        <VisibilityChoice value={visibility} onChange={setVisibility} />
        {error && <p className="text-sm text-red-700">{error}</p>}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <button type="button" onClick={() => setConfirming(true)} className="h-11 px-1 text-[15px] font-medium text-red-700 hover:underline">
            Delete list
          </button>
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className={secondaryButton}>
              Cancel
            </button>
            <button type="submit" disabled={!name.trim() || busy} className={primaryButton}>
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </form>
    </Dialog>
  );
}
