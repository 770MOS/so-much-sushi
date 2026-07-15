"use client";

import { useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import SaveListButton from "@/components/SaveListButton";

type Profile = {
  id: string;
  handle: string;
  display_name: string | null;
  avatar_url: string | null;
};

type StarredEntity = {
  id: string;
  name: string;
  address: string;
  city: string | null;
  state: string | null;
  lat: number;
  lng: number;
  type_name: string | null;
  cuisine_name: string | null;
  status: string;
};

type ProfileList = {
  id: string;
  name: string;
  description: string | null;
  visibility: "private" | "friends" | "public";
  item_count: number;
};

export default function ConnectionProfilePage() {
  const params = useParams<{ handle: string }>();
  const handle = params.handle;
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<Profile | null | undefined>(undefined);
  const [starred, setStarred] = useState<StarredEntity[] | null>(null);
  const [lists, setLists] = useState<ProfileList[] | null>(null);
  const [savedListIds, setSavedListIds] = useState<Set<string>>(new Set());

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
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id, handle, display_name, avatar_url")
        .eq("handle", handle)
        .single();
      if (!cancelled) setProfile(data ?? null);
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, handle]);

  // Own handle - redirect to the full account-management page rather than
  // this read-only connection view.
  useEffect(() => {
    if (user && profile && user.id === profile.id) {
      router.replace("/profile");
    }
  }, [user, profile, router]);

  useEffect(() => {
    if (!profile || user === undefined) return;
    if (user && user.id === profile.id) return; // redirecting to /profile instead

    let cancelled = false;
    (async () => {
      const [{ data: starredData }, { data: listsData }, savedRes] = await Promise.all([
        supabase.rpc("get_profile_starred_entities", { target_user_id: profile.id }),
        supabase.rpc("get_profile_lists", { target_user_id: profile.id }),
        user
          ? supabase.from("saved_lists").select("list_id").eq("user_id", user.id)
          : Promise.resolve({ data: null }),
      ]);
      if (!cancelled) {
        setStarred(starredData ?? []);
        setLists(listsData ?? []);
        setSavedListIds(new Set((savedRes.data ?? []).map((r: { list_id: string }) => r.list_id)));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, profile, user]);

  if (profile === undefined || user === undefined) {
    return (
      <main className="flex min-h-screen flex-1 items-center justify-center bg-white dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
      </main>
    );
  }

  if (profile === null) {
    return (
      <main className="flex min-h-screen flex-1 items-center justify-center bg-white px-6 dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">No profile found for @{handle}.</p>
      </main>
    );
  }

  if (user && user.id === profile.id) {
    // Redirecting to /profile.
    return null;
  }

  const name = profile.display_name?.trim() || profile.handle;
  const initial = (name.charAt(0) || "?").toUpperCase();

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex items-center gap-4">
          {profile.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element -- arbitrary user-supplied external URL, not a local/optimizable asset
            <img
              src={profile.avatar_url}
              alt=""
              className="h-16 w-16 rounded-full object-cover"
            />
          ) : (
            <span className="flex h-16 w-16 items-center justify-center rounded-full bg-primary text-xl font-semibold text-white">
              {initial}
            </span>
          )}
          <div>
            <h1 className="text-xl font-semibold text-zinc-950 dark:text-zinc-50">{name}</h1>
            <p className="text-sm text-zinc-500 dark:text-zinc-400">@{profile.handle}</p>
          </div>
        </div>

        <section className="flex flex-col gap-3">
          <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Starred</h2>
          {starred === null ? (
            <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
          ) : starred.length === 0 ? (
            <p className="text-sm text-zinc-500 dark:text-zinc-400">Nothing to show</p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {starred.map((e) => (
                <li key={e.id} className="flex flex-col gap-0.5 py-3">
                  <span className="font-medium text-zinc-950 dark:text-zinc-50">{e.name}</span>
                  <span className="text-sm text-zinc-500 dark:text-zinc-400">{e.address}</span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-3">
          <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Lists</h2>
          {lists === null ? (
            <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
          ) : lists.length === 0 ? (
            <p className="text-sm text-zinc-500 dark:text-zinc-400">Nothing to show</p>
          ) : (
            <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
              {lists.map((l) => (
                <li key={l.id} className="flex items-center justify-between gap-4 py-3">
                  <Link href={`/lists/${l.id}`} className="flex flex-col gap-0.5">
                    <span className="font-medium text-zinc-950 hover:underline dark:text-zinc-50">
                      {l.name}
                    </span>
                    <span className="text-sm text-zinc-500 dark:text-zinc-400">
                      {l.item_count} {l.item_count === 1 ? "place" : "places"}
                    </span>
                  </Link>
                  {user && (
                    <SaveListButton
                      userId={user.id}
                      listId={l.id}
                      initiallySaved={savedListIds.has(l.id)}
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
