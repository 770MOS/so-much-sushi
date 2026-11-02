// The place record returned by admin_get_place, shared by the admin place and merge screens.

export type Provenance = { source: string; license: string; method: string; set_at: string };
export type SourceRecord = {
  id: number; source: string; contributor: string | null; license: string | null; name: string | null;
  address: string | null; phone: string | null; website: string | null; category: string | null;
  confidence: number | null; operating_status: string | null; match_method: string | null;
};
export type HistoryItem = {
  id: number; type: string; field: string | null; status: string; old: unknown; new: unknown;
  by: string | null; note: string | null; at: string;
};
export type AdminPlace = {
  id: string; name: string; address: string | null; city: string | null; state: string | null;
  postal_code: string | null; phone: string | null; website: string | null; status: string;
  needs_review: boolean; merged_into: string | null; updated_at: string; lat: number; lng: number;
  main_category: string; tags: string[]; saved: { stars: number; lists: number };
  added_by_hand?: boolean; last_checked?: string | null; created_at?: string;
  provenance: Record<string, Provenance>; source_records: SourceRecord[]; history: HistoryItem[];
};

export type PlaceMerge = {
  event_id: number; role: "kept" | "merged"; other_id: string; other_name: string;
  merged_at: string; merged_by: string | null; taken: string[]; undone: boolean;
};

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The fields a merge can take from either place, in the order they are shown.
export const MERGE_FIELDS = ["name", "address", "phone", "website", "location", "main_category", "status"] as const;
export type MergeField = (typeof MERGE_FIELDS)[number];

export function when(iso: string) {
  return new Date(iso).toLocaleDateString("en-US", { year: "numeric", month: "short", day: "numeric", timeZone: "America/New_York" });
}

export function metresBetween(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const r = 6371000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * r * Math.asin(Math.sqrt(h)));
}

// "Overture Maps · CDLA" or "Edited by hand, Oct 24, 2026".
export function provenanceLabel(p: Provenance | undefined) {
  if (!p) return null;
  return p.method === "manual" ? `Edited by hand, ${when(p.set_at)}` : `${p.source} · ${p.license}`;
}

export function statusLabel(s: string) {
  return (
    { active: "Open", temporarily_closed: "Temporarily closed", permanently_closed: "Permanently closed", removed: "Removed", merged: "Merged" }[s] ??
    s.replace(/_/g, " ")
  );
}

// Reads the "keep" radio buttons of a merge form: the fields to take from place B.
export function takenFromB(formData: FormData): MergeField[] {
  return MERGE_FIELDS.filter((f) => formData.get(`keep_${f}`) === "b");
}
