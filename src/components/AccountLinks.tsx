"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { currentUserIsAdmin } from "@/app/actions/account";

const rowClass =
  "flex min-h-12 w-full items-center justify-between px-4 text-left text-base text-zinc-950 hover:bg-zinc-50";

function Chevron() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#a3a3a3" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 6l6 6l-6 6" />
    </svg>
  );
}

// On a phone the account menu and footer aren't there, so the Account tab
// carries their links. Hidden from the medium breakpoint up.
export default function AccountLinks() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [admin, setAdmin] = useState(false);

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

  async function signOut() {
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  return (
    <nav aria-label="Account" className="flex flex-col gap-3 md:hidden">
      <ul className="divide-y divide-line overflow-hidden rounded-[14px] border border-line">
        <li>
          <Link href="/request#your-requests" className={rowClass}>
            Your requests
            <Chevron />
          </Link>
        </li>
        <li>
          <Link href="/request" className={rowClass}>
            Request a place
            <Chevron />
          </Link>
        </li>
        {admin && (
          <li>
            <Link href="/admin" className={rowClass}>
              Admin
              <Chevron />
            </Link>
          </li>
        )}
      </ul>
      <ul className="divide-y divide-line overflow-hidden rounded-[14px] border border-line">
        <li>
          <button type="button" onClick={signOut} className={rowClass}>
            Sign out
          </button>
        </li>
      </ul>
      <p className="px-1 text-xs text-muted">
        Map data © MapTiler © OpenStreetMap contributors · Place data: Overture Maps Foundation, All the Places
      </p>
    </nav>
  );
}
