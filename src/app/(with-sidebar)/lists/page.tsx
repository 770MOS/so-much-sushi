"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SaveListButton from "@/components/SaveListButton";

type MyListRow = {
  id: string;
  name: string;
  visibility: "private" | "friends" | "public";
};

type SharedListRow = {
  id: string;
  name: string;
  description: string | null;
  owner_id: string;
  owner_name: string | null;
  item_count: number;
};

type SavedListRow = {
  id: string;
  name: string;
  description: string | null;
  visibility: "private" | "friends" | "public";
  owner_id: string;
  owner_name: string | null;
  item_count: number;
  saved_at: string;
};

export default function ListsPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [myLists, setMyLists] = useState<MyListRow[] | null>(null);
  const [sharedLists, setSharedLists] = useState<SharedListRow[] | null>(null);
  const [savedLists, setSavedLists] = useState<SavedListRow[] | null>(null);
  const [ownerHandles, setOwnerHandles] = useState<Map<string, string>>(new Map());
  const [error, setError] = useState<string | null>(null);

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

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const [mineRes, sharedRes, savedRes] = await Promise.all([
        supabase
          .from("lists")
          .select("id, name, visibility")
          .eq("owner_id", user.id)
          .order("created_at", { ascending: false }),
        supabase.rpc("get_lists_shared_with_me"),
        supabase.rpc("get_my_saved_lists"),
      ]);
      if (cancelled) return;
      if (mineRes.error || sharedRes.error || savedRes.error) {
        setError("Something went wrong loading your lists.");
      }
      const shared: SharedListRow[] = sharedRes.data ?? [];
      const saved: SavedListRow[] = savedRes.data ?? [];
      setMyLists((mineRes.data as MyListRow[]) ?? []);
      setSharedLists(shared);
      setSavedLists(saved);

      // Neither RPC returns the owner's handle (just owner_id/owner_name),
      // so their /u/[handle] link needs one extra lookup - profiles.handle
      // is in the publicly-readable column allowlist, so this is a plain
      // client-side query, no RPC changes needed.
      const ownerIds = [...new Set([...shared, ...saved].map((l) => l.owner_id))];
      if (ownerIds.length > 0) {
        const { data: owners } = await supabase.from("profiles").select("id, handle").in("id", ownerIds);
        if (!cancelled && owners) {
          setOwnerHandles(
            new Map(
              owners
                .filter((o: { id: string; handle: string | null }) => o.handle)
                .map((o: { id: string; handle: string | null }) => [o.id, o.handle as string])
            )
          );
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user, supabase]);

  function handleUnsaved(listId: string) {
    setSavedLists((prev) => (prev ? prev.filter((l) => l.id !== listId) : prev));
  }

  // A shared list can also already be saved - cross-reference so its button
  // in "Shared with me" doesn't contradict the one in "Saved" for the same
  // list.
  const savedIds = useMemo(() => new Set((savedLists ?? []).map((l) => l.id)), [savedLists]);

  function OwnerName({ ownerId, ownerName }: { ownerId: string; ownerName: string | null }) {
    const label = ownerName ?? "Unknown";
    const handle = ownerHandles.get(ownerId);
    if (!handle) return <>{label}</>;
    return (
      <Link href={`/u/${handle}`} className="hover:underline">
        {label}
      </Link>
    );
  }

  if (user === undefined || myLists === null || sharedLists === null || savedLists === null) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-white px-6 dark:bg-black">
        {error ? (
          <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
        ) : (
          <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
        )}
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-3xl flex-col gap-10">
        <div className="flex items-start justify-between gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">Lists</h1>
            <p className="text-zinc-600 dark:text-zinc-400">
              Lists you own, lists shared with you, and lists you&apos;ve saved.
            </p>
          </div>
          <Link
            href="/"
            className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Back to search
          </Link>
        </div>

        {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

        <section className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">My Lists</h2>
            <Link
              href="/lists/new"
              className="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover"
            >
              Create list
            </Link>
          </div>
          {myLists.length === 0 ? (
            <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
              You haven&apos;t created any lists yet.
            </p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {myLists.map((l) => (
                <li key={l.id} className="py-3">
                  <Link href={`/lists/${l.id}`} className="flex flex-col gap-0.5">
                    <span className="font-medium text-zinc-950 hover:underline dark:text-zinc-50">
                      {l.name}
                    </span>
                    <span className="text-sm text-zinc-500 dark:text-zinc-400">
                      {l.visibility}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-3">
          <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Shared with me</h2>
          {sharedLists.length === 0 ? (
            <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
              No lists have been shared with you yet.
            </p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {sharedLists.map((l) => (
                <li key={l.id} className="flex items-center justify-between gap-4 py-3">
                  <div className="flex flex-col gap-0.5">
                    <Link
                      href={`/lists/${l.id}`}
                      className="font-medium text-zinc-950 hover:underline dark:text-zinc-50"
                    >
                      {l.name}
                    </Link>
                    <span className="text-sm text-zinc-500 dark:text-zinc-400">
                      by <OwnerName ownerId={l.owner_id} ownerName={l.owner_name} /> ·{" "}
                      {l.item_count} {l.item_count === 1 ? "place" : "places"}
                    </span>
                  </div>
                  {user && (
                    <SaveListButton
                      userId={user.id}
                      listId={l.id}
                      initiallySaved={savedIds.has(l.id)}
                      onChange={(saved) => {
                        if (!saved) handleUnsaved(l.id);
                      }}
                    />
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-3">
          <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Saved</h2>
          {savedLists.length === 0 ? (
            <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
              You haven&apos;t saved any lists yet.
            </p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {savedLists.map((l) => (
                <li key={l.id} className="flex items-center justify-between gap-4 py-3">
                  <div className="flex flex-col gap-0.5">
                    <Link
                      href={`/lists/${l.id}`}
                      className="font-medium text-zinc-950 hover:underline dark:text-zinc-50"
                    >
                      {l.name}
                    </Link>
                    <span className="text-sm text-zinc-500 dark:text-zinc-400">
                      by <OwnerName ownerId={l.owner_id} ownerName={l.owner_name} /> ·{" "}
                      {l.visibility} · {l.item_count} {l.item_count === 1 ? "place" : "places"}
                    </span>
                  </div>
                  {user && (
                    <SaveListButton
                      userId={user.id}
                      listId={l.id}
                      initiallySaved={true}
                      onChange={(saved) => {
                        if (!saved) handleUnsaved(l.id);
                      }}
                    />
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </main>
  );
}
