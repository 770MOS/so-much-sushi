"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";
import { currentUserIsAdmin } from "@/app/actions/account";

type Props = {
  supabase: SupabaseClient;
  email: string;
  firstName: string | null;
  displayName: string | null;
  handle: string | null;
  avatarUrl: string | null;
};

function resolveFirstName(
  firstName: string | null,
  displayName: string | null,
  handle: string | null,
  email: string
) {
  if (firstName && firstName.trim()) return firstName.trim();
  // Fallback for accounts from before profiles.first_name existed - derive
  // it the old way instead of leaving the greeting blank.
  const source = (displayName && displayName.trim()) || (handle && handle.trim()) || email;
  return source.includes(" ") ? source.split(" ")[0] : source;
}

const itemClass =
  "flex min-h-11 w-full items-center rounded-lg px-3 text-left text-[15px] text-zinc-950 hover:bg-zinc-100";

export default function AccountMenu({ supabase, email, firstName, displayName, handle, avatarUrl }: Props) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [admin, setAdmin] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);

  const name = resolveFirstName(firstName, displayName, handle, email);
  const initial = (name.charAt(0) || "?").toUpperCase();

  // Only decides whether the Admin link shows; admin pages check for themselves.
  useEffect(() => {
    let cancelled = false;
    currentUserIsAdmin()
      .then((yes) => {
        if (!cancelled) setAdmin(yes);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  // Close on a click outside the menu or on Escape.
  useEffect(() => {
    if (!open) return;
    function onPointerDown(e: PointerEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) setOpen(false);
    }
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  async function handleSignOut() {
    setOpen(false);
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  const close = () => setOpen(false);

  return (
    <div ref={wrapRef} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label="Account menu"
        className={`flex h-11 w-11 items-center justify-center rounded-full ${open ? "ring-[3px] ring-black/15" : ""}`}
      >
        {avatarUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- arbitrary user-supplied external URL, not a local/optimizable asset
          <img src={avatarUrl} alt="" className="h-11 w-11 rounded-full object-cover" />
        ) : (
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-[#e9e4f7] text-base font-medium text-[#3b2c7a]">
            {initial}
          </span>
        )}
      </button>

      {open && (
        <div
          role="menu"
          className="absolute right-0 z-30 mt-2 w-64 rounded-xl border border-line bg-white p-1.5 shadow-[0_8px_24px_rgba(0,0,0,0.12)]"
        >
          <p className="truncate px-3 pb-2 pt-1.5 text-sm text-muted">{name}</p>
          <Link href="/settings" role="menuitem" onClick={close} className={itemClass}>
            Account settings
          </Link>
          <Link href="/request#your-requests" role="menuitem" onClick={close} className={itemClass}>
            Your requests
          </Link>
          <Link href="/request" role="menuitem" onClick={close} className={itemClass}>
            Request a place
          </Link>
          {admin && (
            <Link href="/admin" role="menuitem" onClick={close} className={itemClass}>
              Admin
            </Link>
          )}
          <div className="my-1 border-t border-line" />
          <button type="button" role="menuitem" onClick={handleSignOut} className={itemClass}>
            Sign out
          </button>
        </div>
      )}
    </div>
  );
}
