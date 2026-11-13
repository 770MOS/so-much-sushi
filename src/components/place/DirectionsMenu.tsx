"use client";

import { useEffect, useRef, useState } from "react";
import { directionsLinks, type PlaceDetail } from "@/lib/placeDetail";

type Props = {
  place: Pick<PlaceDetail, "name" | "address" | "lat" | "lng">;
  // "link": blue text in the address row; "button": a full button (phone sheet, place page).
  look?: "link" | "button";
  align?: "left" | "right";
};

const ROUTE_PATH = "M9 4l-6 3v13l6 -3l6 3l6 -3v-13l-6 3l-6 -3zM9 4v13M15 7v13";

// Directions in Apple Maps or Google Maps: the person picks each time (decided 2026-11-10).
export default function DirectionsMenu({ place, look = "link", align = "right" }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLSpanElement>(null);
  const links = directionsLinks(place);

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

  return (
    <span ref={ref} className={`relative inline-flex ${look === "button" ? "" : "shrink-0"}`}>
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        className={
          look === "button"
            ? "inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border border-line bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50"
            : "text-sm font-medium text-link hover:underline"
        }
      >
        {look === "button" && (
          <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d={ROUTE_PATH} />
          </svg>
        )}
        Directions
      </button>
      {open && (
        <div
          role="menu"
          className={`absolute top-full z-30 mt-1.5 w-48 rounded-xl border border-line bg-white p-1 shadow-[0_12px_30px_rgba(0,0,0,0.12)] ${
            align === "right" ? "right-0" : "left-0"
          }`}
        >
          <a role="menuitem" href={links.apple} target="_blank" rel="noopener noreferrer" onClick={() => setOpen(false)} className="flex min-h-11 items-center rounded-lg px-3 text-[15px] text-zinc-950 hover:bg-zinc-50">
            Apple Maps
          </a>
          <a role="menuitem" href={links.google} target="_blank" rel="noopener noreferrer" onClick={() => setOpen(false)} className="flex min-h-11 items-center rounded-lg px-3 text-[15px] text-zinc-950 hover:bg-zinc-50">
            Google Maps
          </a>
        </div>
      )}
    </span>
  );
}
