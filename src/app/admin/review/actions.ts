"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/admin";
import { takenFromB, UUID } from "@/lib/adminPlace";

function ids(formData: FormData, key: string): number[] {
  return formData
    .getAll(key)
    .map((v) => Number(v))
    .filter((n) => Number.isInteger(n) && n > 0);
}

// Only ever send the admin back to a path inside the review section.
function back(formData: FormData, notice: string): never {
  backTo(String(formData.get("return") ?? ""), notice);
}

function backTo(raw: string, notice: string): never {
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

// One proposal, merged with the field choices made on the one-at-a-time screen.
export async function mergeWithChoices(formData: FormData) {
  const { db, email } = await requireAdmin();
  const proposal = Number(formData.get("id"));
  const a = String(formData.get("a") ?? "");
  const b = String(formData.get("b") ?? "");
  if (!Number.isInteger(proposal) || !UUID.test(a) || !UUID.test(b)) back(formData, "Missing places to merge.");
  const { error } = await db.rpc("admin_merge_places", {
    p_survivor: a,
    p_duplicate: b,
    p_take: takenFromB(formData),
    p_decided_by: email,
    p_note: String(formData.get("note") ?? "").trim() || `review queue proposal ${proposal}`,
    p_proposal: proposal,
    p_fill_empty: false,
  });
  if (error) back(formData, `Could not merge: ${error.message}`);
  back(formData, "Merged. You can undo it from the place's page.");
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

async function decideSourceChanges(formData: FormData, accept: boolean) {
  const { db, email } = await requireAdmin();
  const selected = ids(formData, "id");
  if (selected.length === 0) back(formData, "Nothing was ticked.");
  const { data, error } = await db.rpc("decide_source_changes", {
    p_events: selected,
    p_accept: accept,
    p_decided_by: email,
  });
  if (error) back(formData, `Could not save: ${error.message}`);
  back(formData, accept ? `Applied ${data} changes.` : `Rejected ${data} changes.`);
}

export async function acceptSourceChanges(formData: FormData) {
  await decideSourceChanges(formData, true);
}

export async function rejectSourceChanges(formData: FormData) {
  await decideSourceChanges(formData, false);
}

// A place request turns out to be a place we already have.
export async function linkPlaceRequest(formData: FormData) {
  const { db, email } = await requireAdmin();
  const request = Number(formData.get("request"));
  const place = String(formData.get("place") ?? "").trim();
  if (!Number.isInteger(request) || request <= 0) back(formData, "Missing the request.");
  if (!UUID.test(place)) back(formData, "Choose the place it is, or paste its id.");
  const { error } = await db.rpc("admin_link_place_request", {
    p_id: request,
    p_entity: place,
    p_decided_by: email,
    p_note: String(formData.get("note") ?? "").trim() || null,
  });
  if (error) back(formData, `Could not save: ${error.message}`);
  backTo("/admin/review?type=requests", "Marked as already listed.");
}

// Decline the ticked place requests (or the one on the request screen).
export async function declinePlaceRequests(formData: FormData) {
  const { db, email } = await requireAdmin();
  const selected = ids(formData, "request");
  if (selected.length === 0) back(formData, "Nothing was ticked.");
  const reason = String(formData.get("reason") ?? "").trim();
  const note = String(formData.get("note") ?? "").trim();
  const { data, error } = await db.rpc("admin_decline_place_requests", {
    p_ids: selected,
    p_decided_by: email,
    p_note: [reason, note].filter(Boolean).join(": ") || null,
  });
  if (error) back(formData, `Could not save: ${error.message}`);
  backTo("/admin/review?type=requests", `Declined ${data}.`);
}
