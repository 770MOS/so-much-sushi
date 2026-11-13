"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import Dialog, { fieldClass, primaryButton } from "@/components/lists/Dialog";
import { formatMiles } from "@/lib/lists";

type Hit = { place_id: string; label: string; address: string | null; miles: number | null };

// Add places to a list by name: the nearest places whose names match (the same lookup as the
// What box's place suggestions), each with Add / Added. Places can also be added from any
// place's Add to list button.
export default function AddPlacesDialog({
  listId,
  listName,
  near,
  onList,
  onClose,
}: {
  listId: string;
  listName: string;
  near: { lat: number; lng: number; label?: string } | null;
  onList: Set<string>;
  onClose: (changed: boolean) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<{ q: string; rows: Hit[] } | null>(null);
  const [added, setAdded] = useState<Set<string>>(() => new Set(onList));
  const [changed, setChanged] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  const term = q.trim();
  useEffect(() => {
    if (term.length < 2 || !near) return;
    let cancelled = false;
    const t = setTimeout(() => {
      supabase.rpc("suggest_what", { q: term, ref_lat: near.lat, ref_lng: near.lng }).then(({ data }) => {
        if (cancelled) return;
        const rows = ((data ?? []) as (Hit & { kind: string })[]).filter((r) => r.kind === "place" && r.place_id);
        setHits({ q: term, rows });
      });
    }, 180);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [term, near, supabase]);

  async function toggle(id: string) {
    if (busy) return;
    setBusy(id);
    const on = added.has(id);
    const { error } = on
      ? await supabase.from("list_items").delete().eq("list_id", listId).eq("entity_id", id)
      : await supabase.from("list_items").insert({ list_id: listId, entity_id: id });
    setBusy(null);
    if (error) return;
    setChanged(true);
    setAdded((prev) => {
      const next = new Set(prev);
      if (on) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const rows = hits && hits.q === term ? hits.rows : null;

  return (
    <Dialog title={`Add places to ${listName}`} onClose={() => onClose(changed)} wide>
      <div className="mt-4 flex flex-col gap-3">
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-medium text-zinc-950">Place name</span>
          <input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Start typing a name"
            className={fieldClass}
            autoComplete="off"
          />
        </label>
        {!near ? (
          <p className="text-sm text-muted">
            Search for a place first so we know where to look, or use Add to list on any place.
          </p>
        ) : term.length < 2 ? (
          <p className="text-sm text-muted">
            The nearest matches{near.label ? ` to ${near.label}` : ""} come up as you type. You can also use Add to list on any place.
          </p>
        ) : rows === null ? (
          <p className="text-sm text-muted">Looking…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm text-muted">No places by that name within 25 miles.</p>
        ) : (
          <ul className="flex flex-col">
            {rows.map((r) => {
              const on = added.has(r.place_id);
              return (
                <li key={r.place_id} className="flex items-center gap-3 border-b border-[#f0f0f0] py-2.5">
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate text-[15px] font-medium text-zinc-950">{r.label}</span>
                    <span className="truncate text-[13px] text-muted">
                      {[r.address, r.miles !== null ? formatMiles(Number(r.miles)) : null].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                  <button
                    type="button"
                    onClick={() => toggle(r.place_id)}
                    disabled={busy === r.place_id}
                    aria-pressed={on}
                    className={
                      on
                        ? "inline-flex h-10 shrink-0 items-center rounded-[10px] border border-zinc-950 bg-white px-3.5 text-sm font-medium text-zinc-950"
                        : "inline-flex h-10 shrink-0 items-center rounded-[10px] bg-primary px-3.5 text-sm font-medium text-white hover:bg-primary-hover"
                    }
                  >
                    {on ? "Added ✓" : "Add"}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
        <div className="mt-2 flex justify-end">
          <button type="button" onClick={() => onClose(changed)} className={primaryButton}>
            Done
          </button>
        </div>
      </div>
    </Dialog>
  );
}
