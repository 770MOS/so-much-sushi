"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
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
