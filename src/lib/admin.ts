// Server-only. Never import from a "use client" file: it uses the service role key.
import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createServiceRoleClient } from "@/lib/supabase/serviceRole";

// Confirms the signed-in user is on the admins list, then returns a database
// client that can call the admin functions. Call this at the top of every admin
// page and inside every admin server action: the layout check alone is not
// enough, because actions can be invoked directly.
export async function requireAdmin() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const db = createServiceRoleClient();
  const { data, error } = await db.from("admins").select("user_id").eq("user_id", user.id).maybeSingle();
  if (error) throw new Error(`admin check failed: ${error.message}`);
  // Non-admins get a plain 404 so the section's existence is not advertised.
  if (!data) notFound();

  return { db, email: user.email ?? user.id };
}
