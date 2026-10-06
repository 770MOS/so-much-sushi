// Server-only helpers for the category tree used by the admin screens.
import type { SupabaseClient } from "@supabase/supabase-js";

export type Category = { path: string; name: string; depth: number };

// All categories in tree order: each main category followed by its tags.
export async function loadCategories(db: SupabaseClient): Promise<Category[]> {
  const { data, error } = await db.from("categories").select("name, path");
  if (error) throw new Error(error.message);
  return (data ?? [])
    .map((c) => ({ path: String(c.path), name: String(c.name), depth: String(c.path).split(".").length }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
}

export function mainCategories(all: Category[]) {
  return all.filter((c) => c.depth === 1);
}

export function tagsUnder(all: Category[], main: string) {
  return all.filter((c) => c.depth > 1 && c.path.startsWith(main + "."));
}
