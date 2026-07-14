"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import ConnectionsTab from "@/components/ConnectionsTab";

export default function ConnectionsPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [user, setUser] = useState<User | null | undefined>(undefined);

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
    if (user === null) {
      router.replace("/sign-in");
    }
  }, [user, router]);

  if (user === undefined || user === null) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-white px-6 dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-3xl flex-col gap-8">
        <div className="flex items-start justify-between gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Connections</h1>
            <p className="text-zinc-600 dark:text-zinc-400">
              Find people, manage requests, and see who you&apos;re connected with.
            </p>
          </div>
          <Link
            href="/"
            className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Back to search
          </Link>
        </div>

        <ConnectionsTab userId={user.id} />
      </div>
    </main>
  );
}
