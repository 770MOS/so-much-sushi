"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import Avatar from "@/components/Avatar";
import JoinPanel from "@/components/lists/JoinPanel";
import { VISIBILITY, type Visibility } from "@/lib/lists";
import { currentUserIsAdmin } from "@/app/actions/account";

// The phone's Account tab (mocked 2026-11-12): who you are and how you're shown, your place
// requests, each part of settings with what it's set to, admin for admins, the pages that
// are in the footer on a computer, and signing out. Each row opens its part of
// /settings, where the changes are made.

type Settings = {
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  handle: string | null;
  public_name_full: boolean;
  new_list_visibility: Visibility;
  email_friend_requests: boolean;
  email_place_requests: boolean;
  home_city: string | null;
  home_state: string | null;
};

function Chevron() {
  return (
    <svg viewBox="0 0 24 24" width={18} height={18} fill="none" stroke="#9a9a9a" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 6l6 6l-6 6" />
    </svg>
  );
}

function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="flex flex-col">
      {title && <h2 className="px-1 pb-1.5 text-[13px] font-medium text-muted">{title}</h2>}
      <ul className="overflow-hidden rounded-2xl border border-line bg-white">{children}</ul>
    </section>
  );
}

const rowClass = "flex min-h-[52px] w-full items-center gap-3 border-b border-[#f0f0f0] px-4 py-2 text-left text-base text-zinc-950 last:border-b-0";

function Row({ href, label, value, soon }: { href?: string; label: string; value?: string | null; soon?: boolean }) {
  const inner = (
    <>
      <span className={`flex-1 ${soon ? "text-zinc-400" : ""}`}>{label}</span>
      {value && <span className="max-w-[55%] truncate text-sm text-muted">{value}</span>}
      {soon ? <span className="rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-muted">Soon</span> : <Chevron />}
    </>
  );
  return (
    <li className="border-b border-[#f0f0f0] last:border-b-0">
      {href && !soon ? (
        <Link href={href} className={`${rowClass} border-b-0 hover:bg-zinc-50`}>
          {inner}
        </Link>
      ) : (
        <div className={`${rowClass} border-b-0`}>{inner}</div>
      )}
    </li>
  );
}

export default function AccountHome() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [s, setS] = useState<Settings | null>(null);
  const [admin, setAdmin] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => setUser(session?.user ?? null));
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase.rpc("my_settings").then(({ data, error: err }) => {
      if (cancelled) return;
      if (err || !data) setError("Something went wrong loading your account. Try again in a moment.");
      else setS(data as Settings);
    });
    // Only decides whether the Admin row shows; admin pages check for themselves.
    currentUserIsAdmin()
      .then((yes) => {
        if (!cancelled) setAdmin(yes);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  async function signOut() {
    await supabase.auth.signOut();
    router.push("/");
    router.refresh();
  }

  if (user === null) {
    return (
      <JoinPanel
        icon={<span />}
        title="Sign in to see your account"
        body="Your name, home area, who sees your lists, your place requests and your data live here."
      />
    );
  }

  const first = s?.first_name?.trim() || s?.display_name?.split(/\s+/)[0] || "";
  const last = s?.last_name?.trim() || "";
  const fullName = [first, last].filter(Boolean).join(" ") || s?.display_name || "You";
  const shown = s?.public_name_full || !last ? fullName : `${first} ${last.charAt(0).toUpperCase()}.`;
  const home = [s?.home_city, s?.home_state].filter(Boolean).join(", ");
  const emails = s ? [s.email_friend_requests && "Friends", s.email_place_requests && "Requests"].filter(Boolean).join(", ") || "Off" : null;

  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col gap-6 px-4 pb-10 pt-6">
      <h1 className="px-1 text-3xl font-medium tracking-tight text-zinc-950">Account</h1>
      {error && <p className="text-sm text-red-700">{error}</p>}

      {!s ? (
        <p className="px-1 py-6 text-sm text-muted">{user === undefined || !error ? "Loading…" : ""}</p>
      ) : (
        <>
          <Link href="/settings#profile" className="flex items-center gap-3.5 rounded-2xl border border-line bg-white p-4 hover:bg-zinc-50">
            <Avatar name={fullName} seed={s.handle} size={56} />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="truncate text-lg font-medium text-zinc-950">{fullName}</span>
              {s.handle && <span className="truncate text-sm text-muted">@{s.handle}</span>}
              <span className="text-[13px] text-muted">Shown as “{shown}” on public lists</span>
            </span>
            <Chevron />
          </Link>

          <Group title="Places">
            <Row href="/request#your-requests" label="Your requests" />
            <Row href="/request" label="Request a place" />
          </Group>

          <Group title="Settings">
            <Row href="/settings#signin" label="Sign-in" value="Email and password" />
            <Row href="/settings#home" label="Home area" value={home || "Not set"} />
            <Row href="/settings#privacy" label="New lists" value={VISIBILITY[s.new_list_visibility]?.label} />
            <Row href="/settings#emails" label="Emails" value={emails} />
            <Row href="/settings#data" label="Your data" value="Download" />
          </Group>

          {admin && (
            <Group>
              <Row href="/admin" label="Admin" />
            </Group>
          )}

          <Group title="About">
            <Row label="How it works" soon />
            <Row label="Why no ads or rankings" soon />
            <Row label="Privacy" soon />
            <Row label="Terms" soon />
          </Group>

          <div className="flex flex-col items-center gap-3 pt-2">
            <button
              type="button"
              onClick={signOut}
              className="h-12 w-full rounded-xl border border-[#dddddd] bg-white text-base font-medium text-zinc-950 hover:bg-zinc-50"
            >
              Sign out
            </button>
            <Link href="/settings#account" className="flex h-11 items-center text-sm font-medium text-red-700 underline">
              Delete account
            </Link>
          </div>
        </>
      )}
    </main>
  );
}
