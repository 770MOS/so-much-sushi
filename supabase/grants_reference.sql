-- Reference: table and function grants for so-much-sushi
--
-- Supabase's REST API (PostgREST) enforces plain Postgres GRANTs *in addition
-- to* RLS policies. A table can have perfect RLS and still return
-- "permission denied for table X" (42501) if the connecting role - anon,
-- authenticated, or service_role - was never GRANTed access at all. This bit
-- us repeatedly while building auth/search/starring: every new table or
-- SECURITY DEFINER function surfaced its own missing grant, one at a time.
--
-- This file is the consolidated, re-runnable source of truth for that
-- access. It's idempotent (safe to run repeatedly) and should be run in
-- full after any migration that adds a table, changes a role's access
-- pattern, or adds a function meant to be called over the REST API.
--
-- >>> Whenever you add a new table or RPC function, add its grants here <<<
-- >>> before wiring it into the app - don't wait for a 42501 to tell you. <<<
--
-- Roles:
--   anon           - unauthenticated browser requests (publishable/anon key)
--   authenticated  - signed-in users (their own JWT, via @supabase/ssr)
--   service_role    - trusted server-side scripts (secret key), bypasses RLS

-- =============================================================================
-- categories - public reference data (category tree), admin-edited via NocoDB
--   using a direct Postgres connection, not through these REST roles.
-- =============================================================================
GRANT SELECT ON TABLE categories TO anon, authenticated;
GRANT ALL ON TABLE categories TO service_role;

-- =============================================================================
-- entities, entity_categories - restaurant listings + their category tags.
--   Read exclusively through the search_entities() function below (which is
--   SECURITY DEFINER, so it doesn't need anon/authenticated grants on these
--   tables to work). Written only by scripts/load-restaurants.mjs using the
--   service role key. No client code queries these tables directly, so anon
--   and authenticated get nothing here - revoked explicitly in case a stale
--   grant is still lying around from earlier in development.
-- =============================================================================
REVOKE ALL ON TABLE entities, entity_categories FROM anon, authenticated;
GRANT ALL ON TABLE entities, entity_categories TO service_role;

-- =============================================================================
-- profiles - mirrors auth.users (one row per signed-up user, auto-created by
--   a signup trigger). Read by Header/AccountMenu (own row) and
--   ConnectionsTab (handle search across all rows, hence the public-read
--   policy below). Written directly by the Profile page's AccountSettings
--   section (display_name/handle self-service editing) - this surfaced the
--   same class of gap as friendships did: the "Users update their own
--   profile" RLS policy was already live, but the table-level UPDATE grant
--   was not, so the first save 42501'd. Granted below.
--
--   anon also needs SELECT: the sign-up form checks handle availability
--   (`profiles.select(...).eq("handle", ...)`) before calling signUp(), and
--   at that point the visitor has no session yet - runs as anon, not
--   authenticated. The "Profiles are publicly readable" policy already
--   allowed it; the anon grant didn't exist until this surfaced it as a 401.
--
--   home_city/home_state (added in supabase/add_home_location.sql) are the
--   one exception to "this whole table is publicly readable" - a personal
--   convenience setting, never meant to be visible to anyone but the
--   owner. RLS restricts rows, not columns, so a blanket table-level
--   SELECT grant would otherwise let anyone read anyone's
--   home_city/home_state directly
--   (`profiles?select=home_city,home_state&handle=eq.anyone`), same as
--   any other column, regardless of what the app's own queries choose to
--   select.
--
--   IMPORTANT GOTCHA: `REVOKE SELECT (home_city, home_state) ON TABLE
--   profiles FROM anon, authenticated` does NOT work here and was
--   confirmed live to still leak both columns - column-level and
--   table-level privileges are independent ACL mechanisms in Postgres. A
--   role holding a table-level SELECT grant (below) already covers every
--   column; a column-specific REVOKE only affects privileges that were
--   granted at the column level in the first place, and can't narrow a
--   broader table-level grant. The only way to actually restrict specific
--   columns for a role that otherwise has full table access is to flip
--   it: revoke the table-level grant entirely, then re-grant SELECT on an
--   explicit column allowlist that excludes the sensitive ones - which is
--   what's below instead of a plain `GRANT SELECT ON TABLE profiles`.
--   The owner reads their own home_city/home_state via
--   get_my_home_location() instead, a SECURITY DEFINER function that
--   bypasses column grants entirely (same as every other RPC here
--   bypasses table-level grants).
-- =============================================================================
REVOKE SELECT ON TABLE profiles FROM anon, authenticated;
GRANT SELECT (id, handle, display_name, avatar_url, first_name, last_name, created_at)
  ON TABLE profiles TO anon, authenticated;
GRANT UPDATE ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE profiles TO service_role;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are publicly readable" ON profiles;
CREATE POLICY "Profiles are publicly readable" ON profiles
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

DROP POLICY IF EXISTS "Users update their own profile" ON profiles;
CREATE POLICY "Users update their own profile" ON profiles
  FOR UPDATE
  USING (auth.uid() = id);

-- =============================================================================
-- stars - a signed-in user's saved/starred restaurants. Read back via
--   search_entities()'s is_starred column; written directly by the browser
--   client on toggle, so authenticated needs real INSERT/DELETE grants here
--   (unlike entities/entity_categories, this one isn't behind a SECURITY
--   DEFINER function).
-- =============================================================================
GRANT SELECT, INSERT, DELETE ON TABLE stars TO authenticated;
GRANT ALL ON TABLE stars TO service_role;

ALTER TABLE stars ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own stars" ON stars;
CREATE POLICY "Users can view their own stars" ON stars
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own stars" ON stars;
CREATE POLICY "Users can insert their own stars" ON stars
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their own stars" ON stars;
CREATE POLICY "Users can delete their own stars" ON stars
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- =============================================================================
-- hidden_entities - same shape as stars, for a "hide this restaurant"
--   feature that isn't built in the app yet (search_entities already returns
--   is_hidden, so the column/table exists ahead of the UI). Grants mirror
--   stars' pattern so the feature "just works" once it's wired up - update
--   this block if the real feature ends up needing different rules.
-- =============================================================================
GRANT SELECT, INSERT, DELETE ON TABLE hidden_entities TO authenticated;
GRANT ALL ON TABLE hidden_entities TO service_role;

ALTER TABLE hidden_entities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own hidden entities" ON hidden_entities;
CREATE POLICY "Users can view their own hidden entities" ON hidden_entities
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert their own hidden entities" ON hidden_entities;
CREATE POLICY "Users can insert their own hidden entities" ON hidden_entities
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete their own hidden entities" ON hidden_entities;
CREATE POLICY "Users can delete their own hidden entities" ON hidden_entities
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- =============================================================================
-- friendships - requester_id/addressee_id/status. Backs the Profile page's
--   Connections tab (search by handle, send/accept/decline/cancel requests,
--   remove connections) as well as search_entities()/get_my_starred_entities()'s
--   recommendation labels, which read it as SECURITY DEFINER and so don't
--   need these grants themselves.
--
--   RLS is enabled with real self-scoped policies (requester/addressee must
--   be auth.uid(), matching each of SELECT/INSERT/UPDATE/DELETE below) - this
--   revisits the "revisit before shipping a real friends feature" note that
--   used to be here. The policies were already live when the Connections tab
--   was built, but the table-level GRANTs for INSERT/UPDATE/DELETE were not
--   (RLS policies alone don't grant the underlying privilege - same class of
--   gap this file exists to catch), which surfaced as a 42501 "permission
--   denied for table friendships" the first time the tab tried to send a
--   request. Confirm current policies with:
--     SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE tablename = 'friendships';
-- =============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE friendships TO authenticated;
GRANT ALL ON TABLE friendships TO service_role;

-- =============================================================================
-- lists, list_items - user-created visibility-scoped collections (private/
--   friends/public). Full RLS policies (not bare grants) defined in
--   supabase/lists.sql (SELECT/INSERT/DELETE) and
--   supabase/update_lists_policy.sql (UPDATE, for owner-editable
--   name/description/visibility), since visibility scoping needs real
--   per-row logic, unlike friendships' current stopgap above. Grants
--   repeated here per this file's own policy of tracking every table.
-- =============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE lists TO authenticated;
GRANT SELECT, INSERT, DELETE ON TABLE list_items TO authenticated;
GRANT ALL ON TABLE lists, list_items TO service_role;

-- =============================================================================
-- Functions callable over the REST API (PostgREST /rpc/*)
--
-- >>> STANDING RULE: every SECURITY DEFINER function must explicitly     <<<
-- >>> REVOKE EXECUTE ... FROM PUBLIC, unless anonymous access is         <<<
-- >>> genuinely intended (as it is for search_entities, on purpose).     <<<
--
-- CREATE FUNCTION grants EXECUTE to the PUBLIC pseudo-role by default,
-- silently, unless revoked. Every role - including anon - inherits
-- whatever PUBLIC has, so `GRANT EXECUTE ... TO authenticated` alone does
-- NOT lock a function to signed-in callers: anon can still invoke it via
-- the implicit PUBLIC grant underneath, regardless of what's explicitly
-- granted. `REVOKE EXECUTE ... FROM anon` doesn't fix this either, for the
-- same reason - it only removes anon's own (redundant) grant, not the
-- PUBLIC one anon also inherits through.
--
-- This bit get_profile_starred_entities/get_profile_lists on 2026-07-13
-- (anon could read another user's private-by-default data through them
-- despite only `authenticated` ever being explicitly granted) and, once
-- audited, turned out to already be live on get_list_meta: a fully
-- unauthenticated caller could read a public list's name/description/
-- owner_name with zero session at all - confirmed via a real anonymous
-- curl call before the fix, not just inferred from the SQL. Same
-- audit found get_my_starred_entities, get_list_entities, and the
-- handle_new_user() signup trigger all missing the same REVOKE (the
-- trigger function isn't reachable via REST regardless, since PostgREST
-- doesn't expose functions returning `trigger` as RPC endpoints - revoked
-- anyway for defense-in-depth, not because it was exploitable).
--
-- Confirm any function's real grants with:
--   SELECT grantee, privilege_type FROM information_schema.routine_privileges
--   WHERE routine_name = '<function_name>';
-- `PUBLIC` should never appear there unless the function is meant to be
-- callable by anyone, signed in or not.
-- =============================================================================

-- search_entities: the main search RPC. Must stay SECURITY DEFINER with a
-- locked-down search_path (it reads entities/entity_categories/friendships,
-- none of which anon/authenticated are granted directly - see above). If you
-- ever CREATE OR REPLACE this function, re-add both clauses:
--   SECURITY DEFINER
--   SET search_path = public, extensions   -- extensions: PostGIS lives there
-- Confirm with:
--   SELECT proname, prosecdef FROM pg_proc WHERE proname = 'search_entities';
--   -- prosecdef must be `t`
-- Also: CREATE OR REPLACE only replaces a function whose parameter list
-- matches exactly - changing the parameter list (as when name_query was
-- added) registers a second overload instead, and PostgREST can no longer
-- resolve calls to the old shape (PGRST203). DROP FUNCTION the old
-- signature first when this happens.
-- search_entities is the one function here that's SUPPOSED to be callable
-- by anon - it powers the logged-out-visible Discover/Search/home pages.
-- PUBLIC is deliberately left alone here, not revoked.
GRANT EXECUTE ON FUNCTION search_entities(
  double precision, double precision, double precision, ltree, boolean, boolean, boolean, text
) TO anon, authenticated;

-- get_my_starred_entities: powers the /profile page (Map/Browse tabs). Takes
-- no arguments (reads auth.uid() internally), so only needs a signed-in
-- caller - SECURITY DEFINER, defined in
-- supabase/add_city_and_starred_lookup.sql.
REVOKE EXECUTE ON FUNCTION get_my_starred_entities() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_starred_entities() TO authenticated;

-- get_my_home_location: lets the owner read their own home_city/home_state
-- back, since those two columns have SELECT revoked from anon/authenticated
-- at the column level above (a personal setting, not publicly readable
-- like the rest of profiles) - this SECURITY DEFINER function bypasses
-- that column-level REVOKE the same way every other RPC here bypasses
-- table-level grants. Defined in supabase/add_home_location.sql.
REVOKE EXECUTE ON FUNCTION get_my_home_location() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_home_location() TO authenticated;

-- get_profile_starred_entities, get_profile_lists: power the public-facing
-- connection profile page (/u/[handle]). "Public-facing" means viewable by
-- any signed-in user without a friendship, matching how list visibility
-- works everywhere else in this app - NOT the open internet. Originally
-- shipped granted to anon as well as authenticated (a misreading of "public
-- profile page"); confirmed live that anon could read another user's data
-- through them, corrected same day. Defined in
-- supabase/add_connection_profile_functions.sql.
REVOKE EXECUTE ON FUNCTION get_profile_starred_entities(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION get_profile_lists(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_profile_starred_entities(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_profile_lists(uuid) TO authenticated;

-- get_list_meta, get_list_entities: power the /lists/[id] detail page.
-- Both SECURITY DEFINER, defined in supabase/lists.sql - each re-implements
-- the lists visibility check inline (private/friends/public), since running
-- as owner bypasses lists'/list_items' own RLS policies above. The implicit
-- PUBLIC grant meant a fully unauthenticated caller could read a public
-- list's metadata with zero session at all until this REVOKE was added -
-- confirmed live before the fix, not just inferred from the SQL.
REVOKE EXECUTE ON FUNCTION get_list_meta(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_list_entities(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_list_meta(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_list_entities(uuid) TO authenticated;

-- get_entity_detail: powers /venue/[id] (and its intercepted modal
-- equivalent). This is the SECOND function here that's SUPPOSED to be
-- callable by anon, alongside search_entities above - venue pages need to
-- work for signed-out visitors following a shared link or a search engine
-- crawling sitemap.xml, not just signed-in users. PUBLIC is deliberately
-- left alone here too, not revoked. Defined in supabase/get_entity_detail.sql.
GRANT EXECUTE ON FUNCTION get_entity_detail(uuid) TO anon, authenticated;

-- handle_new_user: the on_auth_user_created signup trigger. Not reachable
-- via PostgREST's RPC surface regardless of grants (functions returning
-- `trigger` aren't exposed as /rpc/* endpoints), so this REVOKE is
-- defense-in-depth rather than a fix for something exploitable - included
-- for consistency with the standing rule above. Defined in
-- supabase/add_handle_to_signup_trigger.sql.
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM PUBLIC;

-- text2ltree: built-in Postgres ltree extension function, not app-specific.
-- Not covered here - extensions manage their own default privileges.

-- rls_auto_enable: appears to be a NocoDB-internal utility function (not
-- called by this app). Not covered here.

-- =============================================================================
-- Explicitly out of scope: NocoDB's own internal tables
-- =============================================================================
-- notification, workspace, workspace_user, xc_knex_migrationsv0,
-- xc_knex_migrationsv0_lock, and everything prefixed nc_* belong to the
-- NocoDB admin UI itself (see .claude or /Users/johnny/Projects/nocodb),
-- not the so-much-sushi app schema. NocoDB connects with its own Postgres
-- role (postgres, via the session pooler) rather than through
-- anon/authenticated/service_role, so these grants don't apply to it and
-- shouldn't be extended to cover it.
