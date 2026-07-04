"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";

type Category = {
  id: string;
  name: string;
  path: string;
};

type SearchResult = {
  id: string;
  name: string;
  address: string;
  miles: number;
  is_starred: boolean;
};

type SortMode = "nearest" | "az";

function categoryIndent(path: string) {
  const depth = (path.match(/\./g) ?? []).length;
  return "    ".repeat(depth);
}

function sortButtonClass(active: boolean) {
  return `rounded-md px-3 py-1 text-sm font-medium transition-colors ${
    active
      ? "bg-zinc-900 text-white dark:bg-zinc-100 dark:text-zinc-900"
      : "text-zinc-600 hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-zinc-100"
  }`;
}

function StarIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={20}
      height={20}
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth={1.5}
      className={filled ? "text-amber-400" : "text-zinc-400"}
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        d="M12 3.5l2.6 5.27 5.82.85-4.21 4.1.99 5.8L12 16.9l-5.2 2.62.99-5.8-4.21-4.1 5.82-.85L12 3.5z"
      />
    </svg>
  );
}

export default function Home() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [user, setUser] = useState<User | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [location, setLocation] = useState("");
  const [radius, setRadius] = useState(10);
  const [categoryPath, setCategoryPath] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [sortMode, setSortMode] = useState<SortMode>("nearest");
  const [starredIds, setStarredIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });
    return () => subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    async function loadCategories() {
      const { data } = await supabase
        .from("categories")
        .select("id, name, path")
        .order("path");
      if (data) setCategories(data);
    }
    loadCategories();
  }, [supabase]);

  const sortedResults = useMemo(() => {
    if (!results) return [];
    if (sortMode === "az") {
      return [...results].sort((a, b) => a.name.localeCompare(b.name));
    }
    return results;
  }, [results, sortMode]);

  async function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!location.trim() || loading) return;

    setLoading(true);
    setError(null);
    setResults(null);

    try {
      const geocodeRes = await fetch(
        `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(location)}`
      );
      const geocodeData = await geocodeRes.json();

      if (!geocodeRes.ok || !geocodeData.length) {
        setError("We couldn't find that location. Try a ZIP code or a fuller address.");
        return;
      }

      const { lat, lon } = geocodeData[0];

      const { data, error: rpcError } = await supabase.rpc("search_entities", {
        ref_lat: parseFloat(lat),
        ref_lng: parseFloat(lon),
        radius_miles: radius,
        category_path: categoryPath || null,
      });

      if (rpcError) {
        setError("Something went wrong while searching. Please try again.");
        return;
      }

      const searchResults: SearchResult[] = data ?? [];
      setResults(searchResults);
      setStarredIds(new Set(searchResults.filter((r) => r.is_starred).map((r) => r.id)));
    } catch {
      setError("Something went wrong. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  async function toggleStar(entityId: string) {
    if (!user) {
      router.push("/sign-in");
      return;
    }

    const isStarred = starredIds.has(entityId);

    if (isStarred) {
      const { error: deleteError } = await supabase
        .from("stars")
        .delete()
        .eq("user_id", user.id)
        .eq("entity_id", entityId);
      if (!deleteError) {
        setStarredIds((prev) => {
          const next = new Set(prev);
          next.delete(entityId);
          return next;
        });
      }
    } else {
      const { error: insertError } = await supabase
        .from("stars")
        .insert({ user_id: user.id, entity_id: entityId });
      if (!insertError) {
        setStarredIds((prev) => new Set(prev).add(entityId));
      }
    }
  }

  return (
    <main className="flex min-h-screen flex-1 flex-col items-center bg-zinc-50 px-6 py-16 dark:bg-black">
      <div className="flex w-full max-w-xl flex-col gap-10">
        <div className="flex items-start justify-between gap-4">
          <div className="flex flex-col gap-2">
            <h1 className="text-2xl font-semibold text-zinc-950 dark:text-zinc-50">
              So Much Sushi
            </h1>
            <p className="text-zinc-600 dark:text-zinc-400">
              Find restaurants near you. No ads, no accounts, just search.
            </p>
          </div>
          <div className="shrink-0 pt-1 text-sm text-zinc-500 dark:text-zinc-400">
            {user ? (
              <span>{user.email}</span>
            ) : (
              <Link href="/sign-in" className="underline hover:text-zinc-900 dark:hover:text-zinc-100">
                Sign in
              </Link>
            )}
          </div>
        </div>

        <form onSubmit={handleSearch} className="flex flex-col gap-8">
          <div className="flex flex-col gap-2">
            <label
              htmlFor="location"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Location
            </label>
            <input
              id="location"
              type="text"
              placeholder="ZIP code or address"
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
            />
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex items-baseline justify-between">
              <label
                htmlFor="radius"
                className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
              >
                Radius
              </label>
              <span className="text-sm text-zinc-500 dark:text-zinc-400">{radius} mi</span>
            </div>
            <input
              id="radius"
              type="range"
              min={1}
              max={25}
              value={radius}
              onChange={(e) => setRadius(Number(e.target.value))}
              className="w-full accent-zinc-900 dark:accent-zinc-100"
            />
          </div>

          <div className="flex flex-col gap-2">
            <label
              htmlFor="category"
              className="text-sm font-medium text-zinc-700 dark:text-zinc-300"
            >
              Category
            </label>
            <select
              id="category"
              value={categoryPath}
              onChange={(e) => setCategoryPath(e.target.value)}
              className="w-full rounded-lg border border-zinc-300 bg-white px-4 py-2.5 text-zinc-950 focus:outline-none focus:ring-2 focus:ring-zinc-400 dark:border-zinc-700 dark:bg-zinc-900 dark:text-zinc-50"
            >
              <option value="">All categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.path}>
                  {categoryIndent(c.path)}
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <button
            type="submit"
            disabled={loading || !location.trim()}
            className="w-full rounded-lg bg-zinc-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-zinc-300"
          >
            {loading ? "Searching…" : "Search"}
          </button>
        </form>

        {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}

        {loading && (
          <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
            Searching…
          </p>
        )}

        {!loading && results !== null && (
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-medium text-zinc-700 dark:text-zinc-300">
                {results.length} {results.length === 1 ? "result" : "results"}
              </h2>
              {results.length > 0 && (
                <div className="flex gap-1 rounded-lg border border-zinc-300 p-0.5 dark:border-zinc-700">
                  <button
                    type="button"
                    onClick={() => setSortMode("nearest")}
                    className={sortButtonClass(sortMode === "nearest")}
                  >
                    Nearest
                  </button>
                  <button
                    type="button"
                    onClick={() => setSortMode("az")}
                    className={sortButtonClass(sortMode === "az")}
                  >
                    A&ndash;Z
                  </button>
                </div>
              )}
            </div>

            {results.length === 0 ? (
              <p className="py-8 text-center text-sm text-zinc-500 dark:text-zinc-400">
                No restaurants found nearby. Try a larger radius or a different category.
              </p>
            ) : (
              <ul className="flex flex-col divide-y divide-zinc-200 dark:divide-zinc-800">
                {sortedResults.map((r) => (
                  <li key={r.id} className="flex items-center justify-between gap-4 py-4">
                    <div className="flex flex-col gap-0.5">
                      <span className="font-medium text-zinc-950 dark:text-zinc-50">
                        {r.name}
                      </span>
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">
                        {r.address}
                      </span>
                    </div>
                    <div className="flex shrink-0 items-center gap-3">
                      <span className="text-sm text-zinc-500 dark:text-zinc-400">
                        {r.miles.toFixed(1)} mi
                      </span>
                      <button
                        type="button"
                        onClick={() => toggleStar(r.id)}
                        aria-label={starredIds.has(r.id) ? "Unstar" : "Star"}
                        aria-pressed={starredIds.has(r.id)}
                        className="rounded p-1 transition-colors hover:bg-zinc-200 dark:hover:bg-zinc-800"
                      >
                        <StarIcon filled={starredIds.has(r.id)} />
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
