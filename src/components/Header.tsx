"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import AccountMenu from "@/components/AccountMenu";

type Profile = {
  display_name: string | null;
  handle: string | null;
  avatar_url: string | null;
};

export default function Header() {
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<Profile | null>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    supabase
      .from("profiles")
      .select("display_name, handle, avatar_url")
      .eq("id", user.id)
      .single()
      .then(({ data }) => {
        if (!cancelled) setProfile(data);
      });
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  return (
    <header className="w-full border-b border-zinc-200 bg-white dark:border-zinc-800 dark:bg-black">
      <div className="flex items-center justify-between gap-4 px-6 py-4">
        <Link href="/" className="text-lg font-semibold text-zinc-950 dark:text-zinc-50">
          So Much Sushi
        </Link>

        {user === undefined ? null : user ? (
          <AccountMenu
            supabase={supabase}
            email={user.email ?? ""}
            displayName={profile?.display_name ?? null}
            handle={profile?.handle ?? null}
            avatarUrl={profile?.avatar_url ?? null}
          />
        ) : (
          <Link
            href="/sign-in"
            className="text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Sign in
          </Link>
        )}
      </div>
    </header>
  );
}
