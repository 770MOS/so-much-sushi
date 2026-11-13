"use server";

import { createClient } from "@/lib/supabase/server";
import { isAdmin } from "@/lib/admin";

// Whether the signed-in person is an admin, so the account menu can show the
// Admin link. Only decides whether a link appears: admin pages and actions
// check for themselves with requireAdmin().
export async function currentUserIsAdmin(): Promise<boolean> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return false;
  return isAdmin(user.id);
}

// Delete the signed-in person's account (account settings). Removes the sign-in, which takes their
// profile, favorites, lists, list places, hidden places and friendships with it (all cascade from
// the account); places they asked us to add stay, without their name. Only ever deletes the
// account of the session making the call.
export async function deleteMyAccount(): Promise<{ ok: boolean }> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false };
  const { createServiceRoleClient } = await import("@/lib/supabase/serviceRole");
  const { error } = await createServiceRoleClient().auth.admin.deleteUser(user.id);
  return { ok: !error };
}
