import { createClient as createSupabaseClient } from "@supabase/supabase-js";

// Server-only - bypasses RLS/grants entirely via the service role key.
// Never import this from a "use client" component or any code path that
// could end up in a browser bundle. SUPABASE_SERVICE_ROLE_KEY has no
// NEXT_PUBLIC_ prefix specifically so Next.js won't inline it client-side,
// but that's a naming convention, not an enforced boundary - be deliberate
// about where this is used.
//
// Currently used only by sitemap.ts, which needs to list every qualifying
// entity - something entities' own grants intentionally don't allow
// through anon/authenticated (see the REVOKE ALL note in
// supabase/grants_reference.sql). Every other read in this app goes
// through a SECURITY DEFINER RPC instead; this is the one place that
// reads the table directly, and only because it runs purely server-side
// with no per-user request context to scope it to anyway.
export function createServiceRoleClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
}
