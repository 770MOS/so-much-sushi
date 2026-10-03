export type MergeRow = {
  event_id: number;
  a_id: string; a_name: string; a_address: string | null; a_city: string | null; a_state: string | null;
  a_phone: string | null; a_website: string | null; a_status: string;
  b_id: string; b_name: string; b_address: string | null; b_city: string | null; b_state: string | null;
  b_phone: string | null; b_website: string | null; b_status: string;
  distance_m: number | null; name_similarity: number | null;
  same_phone: boolean | null; same_website: boolean | null;
};

export type TagRow = {
  event_id: number; entity_id: string; name: string; address: string | null;
  city: string | null; state: string | null; main_category: string;
  tag_path: string; tag_name: string | null; keyword: string | null;
};

export type TagCount = { tag_path: string; tag_name: string | null; pending: number };
