import { createClient } from "@/lib/supabase/server";
import type { EntityDetail } from "@/components/VenueDetail";

// Shared by both the standalone /venue/[id] page and its intercepted modal
// equivalent - same fetch, same RPC, so the two can never drift in what
// they show for the same entity.
export async function getEntityDetail(id: string): Promise<EntityDetail | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_entity_detail", { p_entity_id: id });
  if (error || !data || data.length === 0) return null;
  return data[0] as EntityDetail;
}
