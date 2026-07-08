"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

const inputClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

const selectClass =
  "w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50";

export default function NewList() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [visibility, setVisibility] = useState<"private" | "friends" | "public">("private");
  const [creating, setCreating] = useState(false);
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

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    if (!user || !name.trim() || creating) return;

    setCreating(true);
    setError(null);
    const { error: insertError } = await supabase.from("lists").insert({
      owner_id: user.id,
      name: name.trim(),
      description: description.trim() || null,
      visibility,
    });
    setCreating(false);

    if (insertError) {
      setError("Something went wrong creating the list. Please try again.");
      return;
    }
    router.push("/profile?tab=lists");
  }

  if (user === undefined) {
    return (
      <main className="flex min-h-screen flex-1 flex-col items-center justify-center bg-white px-6 dark:bg-black">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">Loading…</p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-white px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-8">
        <div className="flex items-start justify-between gap-4">
          <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">
            Create a list
          </h1>
          <Link
            href="/profile?tab=lists"
            className="shrink-0 pt-1 text-sm text-zinc-500 underline hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
          >
            Cancel
          </Link>
        </div>

        <form onSubmit={handleCreate} className="flex flex-col gap-4">
          <input
            type="text"
            placeholder="List name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className={inputClass}
            aria-label="List name"
            autoFocus
          />
          <input
            type="text"
            placeholder="Description (optional)"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className={inputClass}
            aria-label="List description"
          />
          <select
            value={visibility}
            onChange={(e) => setVisibility(e.target.value as "private" | "friends" | "public")}
            className={selectClass}
            aria-label="Visibility"
          >
            <option value="private">Private</option>
            <option value="friends">Friends</option>
            <option value="public">Public</option>
          </select>

          {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

          <button
            type="submit"
            disabled={!name.trim() || creating}
            className="rounded-lg bg-primary px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
          >
            {creating ? "Creating…" : "Create list"}
          </button>
        </form>
      </div>
    </main>
  );
}
