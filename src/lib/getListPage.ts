import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { HiddenList, ListPageData } from "@/lib/lists";

// One list as the signed-in person (or a visitor) may see it (public.list_page). Cached per
// request, so the page and its metadata share one call. Null when there's no such list.
export const getListPage = cache(async (id: string): Promise<ListPageData | HiddenList | null> => {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_page", { list_id: id });
  if (error || !data) return null;
  return data as ListPageData | HiddenList;
});

export function isHidden(list: ListPageData | HiddenList): list is HiddenList {
  return "hidden" in list && list.hidden === true;
}
