import { createClient } from "@supabase/supabase-js";

// Every entity needs a main category (entities.main_category_id, one of the four roots).
// Fixtures look the id up by slug through the service role client.
export type MainCategorySlug = "restaurants" | "drinks" | "coffee" | "markets";

const cache = new Map<string, string>();

export async function mainCategoryId(slug: MainCategorySlug = "restaurants"): Promise<string> {
  const cached = cache.get(slug);
  if (cached) return cached;
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
  const { data, error } = await supabase.from("categories").select("id").eq("slug", slug).single();
  if (error || !data) throw new Error(`Main category "${slug}" not found: ${error?.message}`);
  cache.set(slug, data.id);
  return data.id;
}
