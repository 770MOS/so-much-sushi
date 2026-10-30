"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { takenFromB, UUID } from "@/lib/adminPlace";
const FIELDS = ["name", "address", "city", "state", "postal_code", "phone", "website", "status", "main_category"] as const;

export async function savePlace(formData: FormData) {
  const { db, email } = await requireAdmin();
  const id = String(formData.get("id") ?? "");
  if (!UUID.test(id)) throw new Error("bad place id");

  const changes: Record<string, string> = {};
  for (const f of FIELDS) {
    const v = formData.get(f);
    if (v !== null) changes[f] = String(v);
  }
  // An unticked checkbox is simply absent from the form.
  changes.needs_review = formData.get("needs_review") === "on" ? "true" : "false";
  const note = String(formData.get("note") ?? "").trim() || null;
  const tags = formData.getAll("tag").map(String);

  const done = (notice: string): never => {
    revalidatePath("/admin", "layout");
    redirect(`/admin/places/${id}?notice=${encodeURIComponent(notice)}`);
  };

  const edit = await db.rpc("admin_update_place", { p_id: id, p_changes: changes, p_decided_by: email, p_note: note });
  if (edit.error) done(`Not saved: ${edit.error.message}`);
  const tagged = await db.rpc("admin_set_place_tags", { p_id: id, p_tags: tags, p_decided_by: email });
  if (tagged.error) done(`Details saved, but tags were not: ${tagged.error.message}`);

  const fields = Number(edit.data ?? 0);
  const parts = [];
  if (fields > 0) parts.push(`${fields} ${fields === 1 ? "field" : "fields"} changed`);
  if (tagged.data === true) parts.push("tags updated");
  done(parts.length ? `Saved: ${parts.join(", ")}.` : "Nothing was changed.");
}

function goTo(id: string, notice: string): never {
  revalidatePath("/admin", "layout");
  redirect(`/admin/places/${id}?notice=${encodeURIComponent(notice)}`);
}

// Merge place B into place A with the field choices from the merge screen.
export async function mergePlaces(formData: FormData) {
  const { db, email } = await requireAdmin();
  const a = String(formData.get("a") ?? "");
  const b = String(formData.get("b") ?? "");
  if (!UUID.test(a) || !UUID.test(b)) throw new Error("bad place id");
  const { error } = await db.rpc("admin_merge_places", {
    p_survivor: a,
    p_duplicate: b,
    p_take: takenFromB(formData),
    p_decided_by: email,
    p_note: String(formData.get("note") ?? "").trim() || null,
    p_fill_empty: false,
  });
  if (error) {
    revalidatePath("/admin", "layout");
    redirect(`/admin/places/${a}/merge?with=${b}&notice=${encodeURIComponent(`Could not merge: ${error.message}`)}`);
  }
  goTo(a, "Merged. The other place now points here; you can undo it below.");
}

type UndoResult = {
  restored_place: string; fields_restored: string[]; fields_kept_edited_since: string[];
  source_records_returned: number; stars_returned: number; list_items_returned: number;
};

// Undo a merge. Returns to the place the admin was on.
export async function undoMerge(formData: FormData) {
  const { db, email } = await requireAdmin();
  const event = Number(formData.get("event"));
  const here = String(formData.get("here") ?? "");
  if (!Number.isInteger(event) || !UUID.test(here)) throw new Error("bad request");
  const { data, error } = await db.rpc("admin_undo_merge", {
    p_merge_event: event,
    p_decided_by: email,
    p_note: String(formData.get("note") ?? "").trim() || null,
  });
  if (error) goTo(here, `Could not undo: ${error.message}`);
  const r = data as UndoResult;
  const parts = [`Merge undone: ${r.source_records_returned} source ${r.source_records_returned === 1 ? "record" : "records"} returned`];
  if (r.stars_returned) parts.push(`${r.stars_returned} ${r.stars_returned === 1 ? "star" : "stars"}`);
  if (r.list_items_returned) parts.push(`${r.list_items_returned} list ${r.list_items_returned === 1 ? "entry" : "entries"}`);
  let notice = parts.join(", ") + ".";
  if (r.fields_kept_edited_since.length) {
    notice += ` Left as they are because they were edited after the merge: ${r.fields_kept_edited_since.join(", ").replace(/_/g, " ")}.`;
  }
  goTo(here, notice);
}

export type SimilarPlace = {
  id: string; name: string; address: string | null; city: string | null; state: string | null;
  phone: string | null; distance_m: number; reason: string;
};
export type AddPlaceState = {
  values: Record<string, string>; tags?: string[]; error?: string; similar?: SimilarPlace[]; attempt?: number;
};
const ADD_FIELDS = ["name", "address", "city", "state", "postal_code", "phone", "website", "main_category", "status", "lat", "lng", "note"] as const;

// Add a place by hand. The first try shows possible existing matches; ticking
// "add it anyway" saves regardless.
export async function addPlace(prev: AddPlaceState, formData: FormData): Promise<AddPlaceState> {
  const { db, email } = await requireAdmin();
  const values: Record<string, string> = {};
  for (const f of ADD_FIELDS) values[f] = String(formData.get(f) ?? "").trim();
  const tags = formData.getAll("tag").map(String);
  const attempt = (prev.attempt ?? 0) + 1;
  const keep = { values, tags, attempt };

  if (!values.name) return { ...keep, error: "A place needs a name." };
  if (!values.lat || !values.lng) return { ...keep, error: "Place the pin on the map." };
  if (!values.main_category) return { ...keep, error: "Choose a main category." };

  if (formData.get("confirm") !== "on") {
    const { data, error } = await db.rpc("admin_similar_places", {
      p_lat: Number(values.lat), p_lng: Number(values.lng), p_name: values.name, p_phone: values.phone || null,
    });
    if (error) return { ...keep, error: `Could not check for existing places: ${error.message}` };
    const similar = (data ?? []) as SimilarPlace[];
    if (similar.length > 0) return { ...keep, similar };
  }

  const { note, ...place } = values;
  const { data: id, error } = await db.rpc("admin_add_place", { p_values: place, p_decided_by: email, p_note: note || null });
  if (error) return { ...keep, error: `Not saved: ${error.message}` };
  if (tags.length) {
    const tagged = await db.rpc("admin_set_place_tags", { p_id: id, p_tags: tags, p_decided_by: email });
    if (tagged.error) goTo(String(id), `Place added, but tags were not saved: ${tagged.error.message}`);
  }
  goTo(String(id), "Place added.");
}

type BulkResult = { places_changed: number; fields_changed: number; places_with_tag_changes: number; skipped_merged: number };

// Bulk edit from the All places list: the ticked rows, or every place matching the filters.
export async function bulkEdit(formData: FormData) {
  const { db, email } = await requireAdmin();
  const raw = String(formData.get("return") ?? "");
  const returnTo = raw.startsWith("/admin/places") ? raw : "/admin/places";
  const back = (notice: string): never => {
    revalidatePath("/admin", "layout");
    const sep = returnTo.includes("?") ? "&" : "?";
    redirect(`${returnTo}${sep}notice=${encodeURIComponent(notice)}`);
  };

  const changes: Record<string, string> = {};
  const main = String(formData.get("b_main") ?? "");
  const status = String(formData.get("b_status") ?? "");
  const review = String(formData.get("b_review") ?? "");
  if (main) changes.main_category = main;
  if (status) changes.status = status;
  if (review === "true" || review === "false") changes.needs_review = review;
  const addTags = formData.getAll("b_add_tag").map(String);
  const removeTags = formData.getAll("b_remove_tag").map(String);
  const checked = formData.get("b_checked") === "on";
  const hasEdits = Object.keys(changes).length > 0 || addTags.length > 0 || removeTags.length > 0;
  if (!hasEdits && !checked) back("Choose something to change first.");

  let ids = formData.getAll("id").map(String).filter((id) => UUID.test(id));
  if (formData.get("scope") === "all") {
    const f = (k: string) => String(formData.get(`f_${k}`) ?? "") || null;
    const tags = formData.getAll("f_tag").map(String);
    ids = [];
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await db.rpc("admin_search_places", {
        p_q: f("q"), p_state: f("state"), p_city: f("city"), p_zip: f("zip"), p_main: f("main"),
        p_tags: tags.length ? tags : null, p_status: f("status"),
        p_needs_review: f("flag") === "review" ? true : null, p_untagged: f("flag") === "untagged" ? true : null,
        p_origin: ["hand", "unconfirmed", "stale"].includes(f("flag") ?? "") ? f("flag") : null,
        p_limit: 1000, p_offset: offset,
      });
      if (error) back(`Could not list the matching places: ${error.message}`);
      const page = (data ?? []) as { id: string; total: number }[];
      if (page.length && Number(page[0].total) > 5000) back("That's more than 5,000 places. Narrow the filters first.");
      ids.push(...page.map((p) => p.id));
      if (page.length < 1000) break;
    }
  }
  if (!ids.length) back("Nothing was ticked.");

  const note = String(formData.get("b_note") ?? "").trim() || null;
  const parts: string[] = [];
  if (hasEdits) {
    const { data, error } = await db.rpc("admin_bulk_update", {
      p_ids: ids, p_changes: changes, p_add_tags: addTags.length ? addTags : null,
      p_remove_tags: removeTags.length ? removeTags : null, p_decided_by: email, p_note: note,
    });
    if (error) back(`Nothing was changed: ${error.message}`);
    const r = data as BulkResult;
    let s = `Updated ${r.places_changed} of ${ids.length} ${ids.length === 1 ? "place" : "places"}.`;
    if (r.places_changed < ids.length - r.skipped_merged) s += " The rest already had those values.";
    if (r.skipped_merged) s += ` Skipped ${r.skipped_merged} merged.`;
    parts.push(s);
  }
  if (checked) {
    const { data, error } = await db.rpc("admin_mark_checked", { p_ids: ids, p_decided_by: email, p_note: note });
    if (error) back(`${parts.join(" ")} Could not mark as checked: ${error.message}`.trim());
    parts.push(`Marked ${data} as checked.`);
  }
  back(parts.join(" "));
}

// "Checked, still correct" on a place page.
export async function markChecked(formData: FormData) {
  const { db, email } = await requireAdmin();
  const id = String(formData.get("id") ?? "");
  if (!UUID.test(id)) throw new Error("bad place id");
  const { error } = await db.rpc("admin_mark_checked", {
    p_ids: [id], p_decided_by: email, p_note: String(formData.get("note") ?? "").trim() || null,
  });
  goTo(id, error ? `Not saved: ${error.message}` : "Marked as checked today.");
}
