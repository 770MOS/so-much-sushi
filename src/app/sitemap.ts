import type { MetadataRoute } from "next";
import { createServiceRoleClient } from "@/lib/supabase/serviceRole";
import { SITE_URL } from "@/lib/siteUrl";

// Comfortably under Google's documented 50,000-URLs-per-sitemap limit -
// the current dataset (low hundreds of entities) fits in one chunk today,
// but generateSitemaps below chunks by count regardless, so this doesn't
// need revisiting as the dataset grows.
const CHUNK_SIZE = 40_000;

async function countEligibleEntities(): Promise<number> {
  const supabase = createServiceRoleClient();
  const { count, error } = await supabase
    .from("entities")
    .select("id", { count: "exact", head: true })
    .neq("status", "permanently_closed")
    .eq("needs_review", false);
  if (error || count === null) return 0;
  return count;
}

export async function generateSitemaps() {
  const total = await countEligibleEntities();
  const chunkCount = Math.max(1, Math.ceil(total / CHUNK_SIZE));
  return Array.from({ length: chunkCount }, (_, id) => ({ id }));
}

export default async function sitemap({
  id,
}: {
  id: Promise<string>;
}): Promise<MetadataRoute.Sitemap> {
  const chunkIndex = Number(await id);
  const supabase = createServiceRoleClient();

  const start = chunkIndex * CHUNK_SIZE;
  const end = start + CHUNK_SIZE - 1;

  const { data, error } = await supabase
    .from("entities")
    .select("id, last_verified")
    .neq("status", "permanently_closed")
    .eq("needs_review", false)
    .order("id")
    .range(start, end);

  if (error || !data) return [];

  return data.map((entity) => ({
    url: `${SITE_URL}/venue/${entity.id}`,
    // last_verified is null for every entity today (never backfilled) -
    // omitted rather than guessing a date, per the same "don't guess"
    // principle the venue page's hours fallback follows.
    lastModified: entity.last_verified ? new Date(entity.last_verified) : undefined,
  }));
}
