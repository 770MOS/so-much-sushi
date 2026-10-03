"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin";

function ids(formData: FormData, key: string): number[] {
  return formData
    .getAll(key)
    .map((v) => Number(v))
    .filter((n) => Number.isInteger(n) && n > 0);
}

// Only ever send the admin back to a path inside the review section.
function back(formData: FormData, notice: string): never {
  const raw = String(formData.get("return") ?? "");
  const path = raw.startsWith("/admin/review") ? raw : "/admin/review";
  const sep = path.includes("?") ? "&" : "?";
  revalidatePath("/admin", "layout");
  redirect(`${path}${sep}notice=${encodeURIComponent(notice)}`);
}

async function decideMerges(formData: FormData, accept: boolean) {
  const { db, email } = await requireAdmin();
  const selected = ids(formData, "id");
  if (selected.length === 0) back(formData, "Nothing was ticked.");
  const { data, error } = await db.rpc("decide_merge_proposals", {
    p_events: selected,
    p_accept: accept,
    p_decided_by: email,
  });
  if (error) back(formData, `Could not save: ${error.message}`);
  back(formData, accept ? `Merged ${data}.` : `Marked ${data} as different places.`);
}

export async function mergeSelected(formData: FormData) {
  await decideMerges(formData, true);
}

export async function keepSeparateSelected(formData: FormData) {
  await decideMerges(formData, false);
}

async function decideTags(db: Awaited<ReturnType<typeof requireAdmin>>["db"], email: string, events: number[], accept: boolean) {
  if (events.length === 0) return 0;
  const { data, error } = await db.rpc("decide_tag_suggestions", {
    p_events: events,
    p_accept: accept,
    p_decided_by: email,
  });
  if (error) throw new Error(error.message);
  return Number(data ?? 0);
}

export async function acceptTagsSelected(formData: FormData) {
  const { db, email } = await requireAdmin();
  const selected = ids(formData, "id");
  if (selected.length === 0) back(formData, "Nothing was ticked.");
  let n = 0;
  try {
    n = await decideTags(db, email, selected, true);
  } catch (e) {
    back(formData, `Could not save: ${(e as Error).message}`);
  }
  back(formData, `Added ${n} tags.`);
}

export async function rejectTagsSelected(formData: FormData) {
  const { db, email } = await requireAdmin();
  const selected = ids(formData, "id");
  if (selected.length === 0) back(formData, "Nothing was ticked.");
  let n = 0;
  try {
    n = await decideTags(db, email, selected, false);
  } catch (e) {
    back(formData, `Could not save: ${(e as Error).message}`);
  }
  back(formData, `Rejected ${n} suggestions.`);
}

// Accept the ticked rows and reject every other row shown on the page.
export async function acceptTickedRejectRest(formData: FormData) {
  const { db, email } = await requireAdmin();
  const selected = new Set(ids(formData, "id"));
  const rest = ids(formData, "shown").filter((id) => !selected.has(id));
  let accepted = 0;
  let rejected = 0;
  try {
    accepted = await decideTags(db, email, [...selected], true);
    rejected = await decideTags(db, email, rest, false);
  } catch (e) {
    back(formData, `Could not save: ${(e as Error).message}`);
  }
  back(formData, `Added ${accepted} tags, rejected ${rejected}.`);
}
