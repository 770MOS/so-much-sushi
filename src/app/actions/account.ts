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
