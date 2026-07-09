"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { SupabaseClient } from "@supabase/supabase-js";

type Props = {
  supabase: SupabaseClient;
  email: string;
  displayName: string | null;
  handle: string | null;
  avatarUrl: string | null;
};

function firstNameOf(displayName: string | null, handle: string | null, email: string) {
  const source = (displayName && displayName.trim()) || (handle && handle.trim()) || email;
  return source.includes(" ") ? source.split(" ")[0] : source;
}

export default function AccountMenu({ supabase, email, displayName, handle, avatarUrl }: Props) {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  const name = firstNameOf(displayName, handle, email);
  const initial = (name.charAt(0) || "?").toUpperCase();

  async function handleSignOut() {
    setOpen(false);
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-label="Account menu"
        className="flex items-center gap-2 rounded-full py-1 pl-1 pr-3 text-sm font-medium text-zinc-700 transition-colors hover:bg-zinc-100 dark:text-zinc-300 dark:hover:bg-zinc-800"
      >
        {avatarUrl ? (
          // eslint-disable-next-line @next/next/no-img-element -- arbitrary user-supplied external URL, not a local/optimizable asset
          <img src={avatarUrl} alt="" className="h-8 w-8 rounded-full object-cover" />
        ) : (
          <span className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-sm font-semibold text-white">
            {initial}
          </span>
        )}
        <span>{name}</span>
      </button>

      {open && (
        <div className="absolute right-0 z-10 mt-1 w-40 rounded-lg border border-zinc-300 bg-white p-1 shadow-lg dark:border-zinc-700 dark:bg-zinc-900">
          <Link
            href="/profile"
            onClick={() => setOpen(false)}
            className="block rounded px-3 py-1.5 text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
          >
            Profile
          </Link>
          <button
            type="button"
            onClick={handleSignOut}
            className="block w-full rounded px-3 py-1.5 text-left text-sm text-zinc-950 hover:bg-zinc-100 dark:text-zinc-50 dark:hover:bg-zinc-800"
          >
            Sign Out
          </button>
        </div>
      )}
    </div>
  );
}
