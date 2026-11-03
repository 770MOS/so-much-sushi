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

export type SourceChangeRow = {
  event_id: number; event_type: string; entity_id: string; name: string; city: string | null; state: string | null;
  field: string | null; current_value: string | null; proposed_value: string | null; reason: string | null;
  release: string | null; created_at: string;
};

// One place request, as admin_pending_place_requests / admin_get_place_request return it.
export type PlaceRequestRow = {
  id: number; name: string; main_category: string; main_category_name: string;
  address: string | null; city: string | null; state: string | null; postal_code: string | null;
  phone: string | null; website: string | null; note: string | null; lat: number; lng: number;
  status: "pending" | "added" | "already_listed" | "declined";
  entity_id: string | null; decided_by: string | null; decided_at: string | null; decision_note: string | null;
  created_at: string; requested_by: string | null; requested_by_handle: string | null;
  requests_by_this_person: number; possible_matches: number;
};
