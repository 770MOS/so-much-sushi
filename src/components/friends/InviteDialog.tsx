"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import Dialog, { primaryButton, secondaryButton } from "@/components/lists/Dialog";

// Invite a friend: your own link. Anyone who opens it while signed in becomes your friend, so a
// new link can replace it (the old one then stops working).
export default function InviteDialog({ onClose }: { onClose: () => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [code, setCode] = useState<string | null>(null);
  const [error, setError] = useState(false);
  const [copied, setCopied] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    supabase.rpc("my_invite_code").then(({ data, error: err }) => {
      if (cancelled) return;
      if (err || !data) setError(true);
      else setCode(data as string);
    });
    return () => {
      cancelled = true;
    };
  }, [supabase]);

  const link = code && typeof window !== "undefined" ? `${window.location.origin}/invite/${code}` : "";

  async function copy() {
    if (!link) return;
    try {
      if (typeof navigator.share === "function" && window.matchMedia("(pointer: coarse)").matches) {
        await navigator.share({ title: "Join me on So Much Sushi", url: link });
        return;
      }
      await navigator.clipboard.writeText(link);
      setCopied(true);
    } catch {
      // Cancelled, or no clipboard: the link is on screen to copy by hand.
    }
  }

  async function renew() {
    setBusy(true);
    const { data, error: err } = await supabase.rpc("my_invite_code", { renew: true });
    setBusy(false);
    if (!err && data) {
      setCode(data as string);
      setCopied(false);
    }
  }

  return (
    <Dialog title="Invite a friend" onClose={onClose}>
      <p className="mt-2 text-[15px] leading-relaxed text-muted">
        Send this link to a friend. When they open it and sign in or join, you&apos;re friends: you see each other&apos;s favorites
        and lists set to Friends.
      </p>
      {error ? (
        <p className="mt-4 text-sm text-red-700">Something went wrong getting your link. Try again in a moment.</p>
      ) : (
        <div className="mt-4 flex flex-col gap-3">
          <input
            readOnly
            value={link || "…"}
            aria-label="Your invite link"
            onFocus={(e) => e.currentTarget.select()}
            className="w-full rounded-[10px] border border-[#dddddd] bg-zinc-50 px-3.5 py-2.5 text-[15px] text-zinc-950"
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <button type="button" onClick={renew} disabled={busy || !code} className="h-11 px-1 text-sm font-medium text-muted hover:text-zinc-950 hover:underline disabled:opacity-50">
              Get a new link
            </button>
            <div className="flex gap-2">
              <button type="button" onClick={onClose} className={secondaryButton}>
                Done
              </button>
              <button type="button" onClick={copy} disabled={!code} className={primaryButton}>
                {copied ? "Copied" : "Copy link"}
              </button>
            </div>
          </div>
          <p className="text-[13px] text-muted">Anyone with this link can add you as a friend. Getting a new link stops the old one working.</p>
        </div>
      )}
    </Dialog>
  );
}
