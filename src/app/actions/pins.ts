"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/admin";
import type { PinHow, PinMethod } from "@/lib/pins";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type MovePinInput = {
  placeId: string;
  lat: number;
  lng: number;
  how: PinHow;
  method: PinMethod;
  accuracy: number | null;
  note: string;
};

function sentence(message: string) {
  return message.charAt(0).toUpperCase() + message.slice(1).replace(/\.?$/, ".");
}

// An admin moves a place's pin (admin place page or the place panel). Kept like any hand edit:
// no source can move it again. Returns how far it moved, or what went wrong.
export async function movePin(input: MovePinInput): Promise<{ moved?: number; error?: string }> {
  const { db, email } = await requireAdmin();
  if (!UUID.test(input.placeId) || !Number.isFinite(input.lat) || !Number.isFinite(input.lng)) {
    return { error: "That pin can't be saved." };
  }
  const { data, error } = await db.rpc("admin_move_pin", {
    p_id: input.placeId,
    p_lat: input.lat,
    p_lng: input.lng,
    p_how: input.how,
    p_method: input.method,
    p_accuracy: input.method === "gps" ? input.accuracy : null,
    p_note: input.note || null,
    p_decided_by: email,
  });
  if (error) return { error: sentence(error.message) };
  revalidatePath(`/admin/places/${input.placeId}`);
  revalidatePath(`/venue/${input.placeId}`);
  return { moved: Number(data) };
}
