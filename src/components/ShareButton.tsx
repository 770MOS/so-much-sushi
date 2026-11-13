"use client";

import { useState, useSyncExternalStore } from "react";
import { ShareIcon } from "@/components/icons";

type Props = {
  // Relative path (e.g. "/venue/abc123") - resolved against
  // window.location.origin at click time, so this always points at
  // wherever the app is actually running (localhost, a preview deploy,
  // production) without needing a build-time site-URL env var the way
  // sitemap.ts does.
  path: string;
  title: string;
  // "button": icon and word (the place page); "icon": icon only (the place panel's top bar).
  look?: "button" | "icon";
};

function subscribeNoop() {
  return () => {};
}

function getCanShareSnapshot() {
  return typeof navigator !== "undefined" && typeof navigator.share === "function";
}

function getCanShareServerSnapshot() {
  return false;
}

export default function ShareButton({ path, title, look = "button" }: Props) {
  // navigator.share isn't available during SSR - useSyncExternalStore (not
  // an effect + setState) is React's own recommended way to read a
  // browser-only value like this without a hydration mismatch: the server
  // and first client render both use getCanShareServerSnapshot (false),
  // then a real client-side read replaces it.
  const canShare = useSyncExternalStore(
    subscribeNoop,
    getCanShareSnapshot,
    getCanShareServerSnapshot
  );
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  function resolveUrl() {
    return `${window.location.origin}${path}`;
  }

  async function handleClick() {
    if (canShare) {
      try {
        await navigator.share({ title, url: resolveUrl() });
      } catch {
        // User cancelled the native share sheet, or it failed silently -
        // either way there's nothing useful to surface as an error.
      }
      return;
    }
    setOpen((o) => !o);
  }

  async function copyLink() {
    await navigator.clipboard.writeText(resolveUrl());
    setCopied(true);
    setOpen(false);
    setTimeout(() => setCopied(false), 2000);
  }

  function emailLink() {
    const subject = encodeURIComponent(title);
    const body = encodeURIComponent(resolveUrl());
    window.location.href = `mailto:?subject=${subject}&body=${body}`;
    setOpen(false);
  }

  return (
    <div className="relative">
      <button
        type="button"
        onClick={handleClick}
        aria-label={look === "icon" ? (copied ? "Link copied" : "Share") : undefined}
        aria-expanded={canShare ? undefined : open}
        title={look === "icon" && copied ? "Link copied" : undefined}
        className={
          look === "icon"
            ? "inline-flex h-11 w-11 items-center justify-center rounded-[10px] text-zinc-950 hover:bg-zinc-100"
            : "inline-flex h-[42px] items-center gap-1.5 rounded-[10px] border border-[#dddddd] bg-white px-3.5 text-sm font-medium text-zinc-950 hover:bg-zinc-50"
        }
      >
        <ShareIcon />
        {look === "button" && (copied ? "Link copied" : "Share")}
      </button>

      {open && !canShare && (
        <div
          className={`absolute z-30 mt-1.5 w-44 rounded-xl border border-line bg-white p-1 shadow-[0_12px_30px_rgba(0,0,0,0.12)] ${
            look === "icon" ? "right-0" : "left-0"
          }`}
        >
          <button
            type="button"
            onClick={copyLink}
            className="flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-zinc-950 hover:bg-zinc-50"
          >
            Copy link
          </button>
          <button
            type="button"
            onClick={emailLink}
            className="flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-zinc-950 hover:bg-zinc-50"
          >
            Email
          </button>
        </div>
      )}
    </div>
  );
}
