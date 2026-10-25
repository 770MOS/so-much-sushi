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
