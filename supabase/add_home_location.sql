-- Adds home_city/home_state to profiles: a single current value (not a
-- history log) representing the user's own home location - a personal
-- convenience setting (pre-fills the home page's search), never a shared/
-- social field.
--
-- IMPORTANT: profiles has "Profiles are publicly readable"
-- (RLS: USING (true)) plus a blanket GRANT SELECT ON TABLE profiles TO
-- anon, authenticated - correct for display_name/handle/avatar_url (meant
-- to be visible to everyone), wrong for home_city/home_state. RLS
-- restricts rows, not columns, so a row-level policy can't split
-- visibility within the same row between "public" and "owner-only"
-- fields - only not selecting these columns in the app's own queries
-- (e.g. /u/[handle]) would NOT actually block anyone from reading them
-- directly via `profiles?select=home_city,home_state&handle=eq.anyone`
-- using nothing but the public anon key.
--
-- The fix (see the correction comment further below) is to revoke the
-- blanket table-level SELECT entirely and re-grant it as an explicit
-- column allowlist that excludes these two - a column-specific REVOKE
-- alone does NOT work here, since profiles already had a table-level
-- SELECT grant that a column-level REVOKE can't narrow. The owner reads
-- their own home_city/home_state via get_my_home_location() below instead
-- (SECURITY DEFINER, bypasses the table-level grant entirely, same as
-- every other RPC in this project).
--
-- No new grants needed for UPDATE beyond what already exists - profiles
-- already has GRANT UPDATE ON TABLE profiles TO authenticated and the
-- "Users update their own profile" RLS policy (USING (auth.uid() = id)),
-- both of which already cover UPDATE on these new columns (UPDATE isn't
-- column-restricted here - only SELECT is, since UPDATE can't leak
-- existing values and RLS's row check already prevents updating someone
-- else's row).
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS home_city text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS home_state text;

-- CORRECTION: `REVOKE SELECT (home_city, home_state) ON TABLE profiles
-- FROM anon, authenticated` (the original version of this line) does NOT
-- work - confirmed live, anon could still read both columns directly
-- afterward. Column-level and table-level privileges are independent ACL
-- mechanisms in Postgres; a role holding a *table-level* SELECT grant
-- (which profiles already had, from grants_reference.sql, long before
-- this file) already covers every column, and a column-specific REVOKE
-- cannot narrow that - it only has an effect on privileges that were
-- granted at the column level in the first place. The only way to
-- actually restrict specific columns for a role that otherwise has full
-- table access is to flip it: revoke the broad table-level grant
-- entirely, then re-grant SELECT on an explicit column allowlist that
-- excludes the sensitive ones.
REVOKE SELECT ON TABLE profiles FROM anon, authenticated;
GRANT SELECT (id, handle, display_name, avatar_url, first_name, last_name, created_at)
  ON TABLE profiles TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_my_home_location()
 RETURNS TABLE(home_city text, home_state text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $function$
    SELECT p.home_city, p.home_state
    FROM profiles p
    WHERE p.id = auth.uid();
$function$;

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default - explicitly
-- revoked per the standing rule in grants_reference.sql.
REVOKE EXECUTE ON FUNCTION public.get_my_home_location() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_home_location() TO authenticated;

NOTIFY pgrst, 'reload schema';
