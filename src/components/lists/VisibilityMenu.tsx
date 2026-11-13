"use client";

import { useEffect, useRef, useState } from "react";
import { PUBLIC_NOTE, VISIBILITY, VISIBILITY_ORDER, type Visibility } from "@/lib/lists";

export function VisibilityIcon({ v, size = 15 }: { v: Visibility; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={VISIBILITY[v].d} />
    </svg>
  );
}

// Who can see a list, changed in one tap (decided 2026-11-12): Just you, Friends or Public.
// Picking Public shows that anyone can find it, including on Google, with the owner's name.
export default function VisibilityMenu({ value, onChange }: { value: Visibility; onChange: (v: Visibility) => Promise<boolean> }) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState(false);
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

  async function pick(v: Visibility) {
    setOpen(false);
    if (v === value) return;
    setBusy(true);
    const ok = await onChange(v);
    setBusy(false);
    setNote(ok && v === "public");
  }

  return (
    <div ref={ref} className="relative inline-flex flex-col items-start">
      <button
        type="button"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={`Who can see this list: ${VISIBILITY[value].label}`}
        disabled={busy}
        onClick={() => setOpen((o) => !o)}
        className="inline-flex h-9 items-center gap-1.5 rounded-full border border-[#dddddd] bg-white pl-3 pr-2.5 text-[13px] font-medium text-zinc-950 hover:border-zinc-400 disabled:opacity-60"
      >
        <VisibilityIcon v={value} />
        {VISIBILITY[value].label}
        <svg viewBox="0 0 24 24" width={14} height={14} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 9l6 6l6 -6" />
        </svg>
      </button>
      {open && (
        <ul role="listbox" aria-label="Who can see this list" className="absolute left-0 top-full z-30 mt-2 w-72 rounded-xl border border-line bg-white p-1 shadow-[0_8px_24px_rgba(0,0,0,0.12)]">
          {VISIBILITY_ORDER.map((v) => (
            <li key={v} role="option" aria-selected={v === value}>
              <button
                type="button"
                onClick={() => pick(v)}
                className={`flex min-h-12 w-full items-start gap-2.5 rounded-lg px-3 py-2 text-left hover:bg-zinc-50 ${v === value ? "bg-zinc-50" : ""}`}
              >
                <span className="mt-0.5 text-zinc-700">
                  <VisibilityIcon v={v} size={17} />
                </span>
                <span className="flex flex-col">
                  <span className="text-[15px] font-medium text-zinc-950">{VISIBILITY[v].label}</span>
                  <span className="text-[13px] text-muted">{v === "public" ? PUBLIC_NOTE : VISIBILITY[v].help}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
      {note && value === "public" && (
        <p role="status" className="mt-1.5 max-w-xs text-[13px] text-muted">
          {PUBLIC_NOTE}
        </p>
      )}
    </div>
  );
}
