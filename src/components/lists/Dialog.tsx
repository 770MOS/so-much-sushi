"use client";

import { useEffect, useRef, type ReactNode } from "react";

// A small centred dialog for the list pages (New list, Edit list, Add places). Escape and a
// click outside close it; focus goes to its first field.
export default function Dialog({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  const boxRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    boxRef.current?.querySelector<HTMLElement>("input, textarea, select, button")?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/30 sm:items-center sm:px-6" onClick={onClose}>
      <div
        ref={boxRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className={`flex max-h-[90dvh] w-full flex-col overflow-y-auto rounded-t-2xl bg-white p-6 shadow-[0_12px_40px_rgba(0,0,0,0.2)] sm:rounded-2xl ${wide ? "sm:max-w-lg" : "sm:max-w-md"}`}
      >
        <h2 className="text-xl font-medium text-zinc-950">{title}</h2>
        {children}
      </div>
    </div>
  );
}

export const fieldClass =
  "w-full rounded-[10px] border border-[#dddddd] bg-white px-3.5 py-2.5 text-[15px] text-zinc-950 placeholder:text-[#707070] focus:border-zinc-950 focus:outline-none";
export const primaryButton =
  "inline-flex h-11 items-center justify-center rounded-[10px] bg-primary px-5 text-[15px] font-medium text-white hover:bg-primary-hover disabled:opacity-50";
export const secondaryButton =
  "inline-flex h-11 items-center justify-center rounded-[10px] border border-[#dddddd] bg-white px-5 text-[15px] font-medium text-zinc-950 hover:bg-zinc-50 disabled:opacity-50";
