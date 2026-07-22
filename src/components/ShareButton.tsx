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

export default function ShareButton({ path, title }: Props) {
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
        aria-label="Share"
        aria-expanded={canShare ? undefined : open}
        className="flex items-center gap-1.5 rounded-lg border border-zinc-300 px-3 py-2 text-sm text-zinc-700 transition-colors hover:bg-zinc-100 dark:border-zinc-700 dark:text-zinc-300 dark:hover:bg-zinc-800"
      >
        <ShareIcon />
        {copied ? "Copied!" : "Share"}
      </button>

      {open && !canShare && (
        <div className="absolute left-0 z-10 mt-1 w-40 rounded-lg border border-zinc-300 bg-white p-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
          <button
            type="button"
            onClick={copyLink}
            className="w-full rounded px-2 py-1.5 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
          >
            Copy link
          </button>
          <button
            type="button"
            onClick={emailLink}
            className="w-full rounded px-2 py-1.5 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
          >
            Email
          </button>
        </div>
      )}
    </div>
  );
}
