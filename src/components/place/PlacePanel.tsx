"use client";

import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { useRouter } from "next/navigation";
import { useIsDesktop } from "@/lib/useIsDesktop";
import { takeSheetStart, type SheetStart } from "@/lib/placePanel";
import type { PlaceDetail } from "@/lib/placeDetail";
import ShareButton from "@/components/ShareButton";
import PlaceBody from "@/components/place/PlaceBody";

// A place opened from a page (decided 2026-11-10). The address changes to the place's own link
// (/venue/<id>), Back closes it, and opening that link directly shows the full place page.
//   * Computer: a panel on the right, 440px wide, below the page's header and filter bar, with
//     nothing dimmed behind it, so the list stays usable and the map keeps the pin in view.
//     Its top bar: open as a full page, Share, Close.
//   * Phone: a bottom sheet. From a map it opens as a short card (swipe or tap the handle up
//     for the whole place, down to close); from a list it opens at full height.
// place null: still loading (the panel shows straight away, then fills in); "missing": gone.

const PANEL_WIDTH = 440;

// Where the panel starts: below the element the page marks with data-place-panel-top (the
// results page's filter bar), else below the header; at the top once those scroll away.
function usePanelTop() {
  const [top, setTop] = useState(0);
  useEffect(() => {
    let frame = 0;
    function measure() {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const anchor = document.querySelector("[data-place-panel-top]") ?? document.querySelector("header");
        setTop(anchor ? Math.max(0, Math.round(anchor.getBoundingClientRect().bottom)) : 0);
      });
    }
    measure();
    window.addEventListener("scroll", measure, { passive: true });
    window.addEventListener("resize", measure);
    const observer = new ResizeObserver(measure);
    observer.observe(document.body);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", measure);
      window.removeEventListener("resize", measure);
      observer.disconnect();
    };
  }, []);
  return top;
}

function IconLink({ href, label, children }: { href: string; label: string; children: React.ReactNode }) {
  // A plain link, not Next's: it loads the full place page instead of reopening this panel.
  return (
    <a href={href} aria-label={label} title={label} className="inline-flex h-11 w-11 items-center justify-center rounded-[10px] text-zinc-950 hover:bg-zinc-100">
      {children}
    </a>
  );
}

function CloseButton({ onClose }: { onClose: () => void }) {
  return (
    <button type="button" onClick={onClose} aria-label="Close" className="inline-flex h-11 w-11 items-center justify-center rounded-[10px] text-zinc-950 hover:bg-zinc-100">
      <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
        <path d="M18 6l-12 12M6 6l12 12" />
      </svg>
    </button>
  );
}

function FullPageIcon() {
  return (
    <svg viewBox="0 0 24 24" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 6h-6a2 2 0 0 0 -2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-6M11 13l9 -9M15 4h5v5" />
    </svg>
  );
}

function Body({ place, layout }: { place: PlaceDetail | null | "missing"; layout: "panel" | "sheet" }) {
  if (place === "missing") {
    return <p className="text-[15px] text-muted">This place isn’t listed any more.</p>;
  }
  if (!place) {
    return (
      <div className="flex flex-col gap-4" aria-busy="true" aria-label="Loading the place">
        <div className="h-8 w-3/4 rounded-lg bg-zinc-100" />
        <div className="h-4 w-1/2 rounded bg-zinc-100" />
        <div className="flex gap-2">
          <div className="h-[42px] w-28 rounded-[10px] bg-zinc-100" />
          <div className="h-[42px] w-32 rounded-[10px] bg-zinc-100" />
        </div>
        <div className="h-40 rounded-lg bg-zinc-50" />
      </div>
    );
  }
  return <PlaceBody place={place} layout={layout} headingId="place-panel-name" />;
}

export default function PlacePanel({ place }: { place: PlaceDetail | null | "missing" }) {
  const router = useRouter();
  const isDesktop = useIsDesktop();
  const top = usePanelTop();
  const id = place && place !== "missing" ? place.id : null;
  const name = place && place !== "missing" ? place.name : "";

  function close() {
    router.back();
  }

  // Move to the place's name when it opens, so a keyboard or screen reader lands in the panel.
  useEffect(() => {
    if (id) document.getElementById("place-panel-name")?.focus({ preventScroll: true });
  }, [id]);

  // Escape closes, unless a menu or dialog is open anywhere (that closes first).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== "Escape" || e.defaultPrevented) return;
      if (document.querySelector('[aria-expanded="true"], [role="dialog"][aria-modal="true"]')) return;
      router.back();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [router]);

  if (isDesktop === null) return null;

  if (isDesktop) {
    return (
      <aside
        data-place-panel
        aria-labelledby={id ? "place-panel-name" : undefined}
        aria-label={id ? undefined : "Place"}
        style={{ top, width: PANEL_WIDTH }}
        className="fixed bottom-0 right-0 z-30 flex max-w-full flex-col border-l border-line bg-white shadow-[-8px_0_24px_rgba(0,0,0,0.06)]"
      >
        <div className="flex h-14 shrink-0 items-center justify-end gap-1 border-b border-[#f0f0f0] px-2.5">
          {id && (
            <>
              <IconLink href={`/venue/${id}`} label="Open as a full page">
                <FullPageIcon />
              </IconLink>
              <ShareButton path={`/venue/${id}`} title={name} look="icon" />
            </>
          )}
          <CloseButton onClose={close} />
        </div>
        <div className="flex-1 overflow-y-auto px-6 pb-6 pt-[22px]">
          <Body place={place} layout="panel" />
        </div>
      </aside>
    );
  }

  return <PhoneSheet place={place} onClose={close} />;
}

// ---------------------------------------------------------------- phone sheet

function PhoneSheet({ place, onClose }: { place: PlaceDetail | null | "missing"; onClose: () => void }) {
  const [state, setState] = useState<SheetStart>(() => takeSheetStart());
  const [drag, setDrag] = useState(0); // how far the sheet is pulled (px, down is positive)
  const start = useRef<{ y: number; t: number } | null>(null);
  const id = place && place !== "missing" ? place.id : null;
  const name = place && place !== "missing" ? place.name : "";

  function onDown(e: ReactPointerEvent) {
    start.current = { y: e.clientY, t: Date.now() };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }
  function onMove(e: ReactPointerEvent) {
    if (start.current) setDrag(e.clientY - start.current.y);
  }
  function onUp(e: ReactPointerEvent) {
    const s = start.current;
    start.current = null;
    const dy = s ? e.clientY - s.y : 0;
    setDrag(0);
    if (Math.abs(dy) < 8) {
      // A tap on the handle: open fully, or back to the card.
      setState((st) => (st === "peek" ? "full" : "peek"));
      return;
    }
    if (dy < -50) setState("full");
    else if (dy > 50) {
      if (state === "full") setState("peek");
      else onClose();
    }
  }

  const height = state === "full" ? "calc(100dvh - 16px)" : "46dvh";

  return (
    <section
      data-place-panel
      aria-labelledby={id ? "place-panel-name" : undefined}
      aria-label={id ? undefined : "Place"}
      style={{ height, transform: drag ? `translateY(${Math.max(drag, -200)}px)` : undefined }}
      className={`fixed inset-x-0 bottom-0 z-50 flex flex-col rounded-t-[20px] bg-white shadow-[0_-6px_24px_rgba(0,0,0,0.12)] ${
        drag ? "" : "transition-[height,transform] duration-200 ease-out"
      }`}
    >
      <div className="flex shrink-0 items-center gap-1 px-2 pt-1">
        <button
          type="button"
          aria-label={state === "full" ? "Show less" : "Show more"}
          onPointerDown={onDown}
          onPointerMove={onMove}
          onPointerUp={onUp}
          onPointerCancel={() => {
            start.current = null;
            setDrag(0);
          }}
          className="flex h-11 flex-1 touch-none items-center justify-center"
        >
          <span className="h-[5px] w-10 rounded-full bg-[#d6d6d6]" />
        </button>
      </div>
      <div className="absolute right-2 top-1 flex items-center">
        {id && <ShareButton path={`/venue/${id}`} title={name} look="icon" />}
        <CloseButton onClose={onClose} />
      </div>
      <div className={`flex-1 px-5 pb-8 ${state === "full" ? "overflow-y-auto" : "overflow-hidden"}`}>
        <Body place={place} layout="sheet" />
      </div>
    </section>
  );
}
