"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export type Category = { path: string; name: string };

// The category list (85 rows) loaded once per visit and shared, for showing a kind's name
// from its path ("restaurants.italian" -> "Italian").
let cache: Promise<Category[]> | null = null;

function load(): Promise<Category[]> {
  if (!cache) {
    cache = Promise.resolve(
      createClient()
        .from("categories")
        .select("path, name")
        .order("path")
        .then(({ data }) => (data ?? []) as Category[])
    ).catch(() => {
      cache = null;
      return [];
    });
  }
  return cache;
}

export function useCategoryNames(): Map<string, string> {
  const [names, setNames] = useState<Map<string, string>>(new Map());
  useEffect(() => {
    let cancelled = false;
    load().then((rows) => {
      if (!cancelled) setNames(new Map(rows.map((c) => [c.path, c.name])));
    });
    return () => {
      cancelled = true;
    };
  }, []);
  return names;
}
