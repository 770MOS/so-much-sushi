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
--   a signup trigger). Not yet read directly by any client code; scoped to
--   each user's own row for when it is (e.g. a future profile/handle page).
-- =============================================================================
GRANT SELECT ON TABLE profiles TO authenticated;
GRANT ALL ON TABLE profiles TO service_role;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

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
-- friendships - requester_id/addressee_id/status. Not a built feature yet,
--   but a bare `GRANT SELECT ... TO authenticated` was required today to
--   unblock inserting/deleting stars (a trigger or downstream check reads
--   friendships to compute is_recommended, running as the authenticated
--   caller, not as a SECURITY DEFINER owner). That bare grant is CONFIRMED
--   WORKING but currently lets any signed-in user read every row in the
--   table - fine for now (nothing in the app surfaces it), but revisit
--   before shipping a real friends feature.
--
--   A tightened, self-scoped policy is included below but commented out:
--   it was NOT tested against whatever exactly reads friendships today, so
--   flipping it on could break starring again if that check needs to see
--   rows where the current user isn't requester or addressee. Test starring
--   again after enabling it.
-- =============================================================================
GRANT SELECT ON TABLE friendships TO authenticated;
GRANT ALL ON TABLE friendships TO service_role;

-- ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;
--
-- DROP POLICY IF EXISTS "Users can view their own friendships" ON friendships;
-- CREATE POLICY "Users can view their own friendships" ON friendships
--   FOR SELECT TO authenticated
--   USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- =============================================================================
-- Functions callable over the REST API (PostgREST /rpc/*)
-- =============================================================================

-- search_entities: the main search RPC. Must stay SECURITY DEFINER with a
-- locked-down search_path (it reads entities/entity_categories/friendships,
-- none of which anon/authenticated are granted directly - see above). If you
-- ever CREATE OR REPLACE this function, re-add both clauses:
--   SECURITY DEFINER
--   SET search_path = public
-- Confirm with:
--   SELECT proname, prosecdef FROM pg_proc WHERE proname = 'search_entities';
--   -- prosecdef must be `t`
GRANT EXECUTE ON FUNCTION search_entities(
  double precision, double precision, double precision, ltree, boolean, boolean
) TO anon, authenticated;

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
