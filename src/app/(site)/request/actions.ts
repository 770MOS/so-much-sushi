"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type RequestMatch = {
  id: string; name: string; address: string | null; city: string | null; state: string | null; distance_m: number;
};
export type RequestState = {
  values: Record<string, string>;
  error?: string;
  matches?: RequestMatch[];
  // Set once a request is sent: its id and name, for the confirmation.
  sent?: { id: number; name: string };
  attempt?: number;
};

const FIELDS = ["name", "main_category", "lat", "lng", "address", "city", "state", "postal_code", "phone", "website", "note"] as const;

// The database's messages are written for people; give them a capital letter.
function sentence(message: string) {
  const m = message.replace(/^.*?:\s*(?=[a-z])/, "");
  return m.charAt(0).toUpperCase() + m.slice(1) + (m.endsWith(".") ? "" : ".");
}

// Request a place. The first try shows places we may already have; ticking
// "none of these" sends the request regardless.
export async function submitPlaceRequest(prev: RequestState, formData: FormData): Promise<RequestState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const values: Record<string, string> = {};
  for (const f of FIELDS) values[f] = String(formData.get(f) ?? "").trim();
  const attempt = (prev.attempt ?? 0) + 1;
  const keep = { values, attempt };
  if (!user) return { ...keep, error: "Sign in to request a place." };

  if (!values.name) return { ...keep, error: "What is the place called?" };
  if (!values.main_category) return { ...keep, error: "Choose what kind of place it is." };
  if (!values.lat || !values.lng) return { ...keep, error: "Place the pin on the map." };
  const ownKnowledge = formData.get("own_knowledge") === "on";
  if (ownKnowledge) values.own_knowledge = "on";
  if (!ownKnowledge) return { ...keep, error: "Please confirm where the details come from." };

  if (formData.get("none_match") !== "on") {
    const { data, error } = await supabase.rpc("request_similar_places", {
      p_lat: Number(values.lat), p_lng: Number(values.lng), p_name: values.name, p_phone: values.phone || null,
    });
    if (error) return { ...keep, error: "Something went wrong checking for the place. Please try again." };
    const matches = (data ?? []) as RequestMatch[];
    if (matches.length > 0) return { ...keep, matches };
  }

  const { data: id, error } = await supabase.rpc("submit_place_request", {
    p_values: { ...values, own_knowledge: "true" },
  });
  if (error) return { ...keep, error: `Not sent. ${sentence(error.message)}` };
  revalidatePath("/request");
  return { values: {}, attempt, sent: { id: Number(id), name: values.name } };
}
