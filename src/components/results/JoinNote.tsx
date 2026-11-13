"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { FriendsFavoriteIcon, FavoriteIcon } from "@/components/icons";

// What a visitor sees on tapping Favorites, Friends, Want to try or a heart (option B,
// decided 2026-11-10): the buttons look normal with a small lock, and say what joining gives.
export default function JoinNote({ open, onClose }: { open: boolean; onClose: () => void }) {
  const firstRef = useRef<HTMLAnchorElement>(null);

  useEffect(() => {
    if (!open) return;
    firstRef.current?.focus();
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 px-6" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="join-note-title"
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-[0_12px_40px_rgba(0,0,0,0.2)]"
      >
        <div className="flex items-center gap-2" aria-hidden="true">
          <FavoriteIcon filled size={22} />
          <FriendsFavoriteIcon size={20} />
        </div>
        <h2 id="join-note-title" className="mt-3 text-xl font-medium text-zinc-950">
          Favorites and Friends come with a free account
        </h2>
        <p className="mt-2 text-[15px] leading-relaxed text-muted">
          Save the places you love, keep a Want to try list, and see your friends’ favorites on the map.
        </p>
        <div className="mt-5 flex flex-col gap-2">
          <Link
            ref={firstRef}
            href="/sign-up"
            className="flex h-12 items-center justify-center rounded-xl bg-primary text-base font-medium text-white hover:bg-primary-hover"
          >
            Join free
          </Link>
          <Link
            href="/sign-in"
            className="flex h-12 items-center justify-center rounded-xl border border-[#dddddd] text-base font-medium text-zinc-950 hover:bg-zinc-50"
          >
            Sign in
          </Link>
          <button type="button" onClick={onClose} className="h-11 text-[15px] font-medium text-muted hover:text-zinc-950">
            Not now
          </button>
        </div>
      </div>
    </div>
  );
}
