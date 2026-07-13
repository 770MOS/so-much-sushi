-- Two lookup functions for the public-facing connection profile page
-- (/u/[handle]): get_profile_starred_entities(target_user_id) and
-- get_profile_lists(target_user_id). Already applied directly in the
-- Supabase SQL Editor.
--
-- IMPORTANT PROVENANCE NOTE: unlike other tracked function files in this
-- directory, this one is NOT a verbatim pg_get_functiondef pull - only the
-- two function signatures were confirmed that way. This body is a
-- reconstruction, modeled directly on get_my_starred_entities() (in
-- add_city_and_starred_lookup.sql) and get_list_meta()/get_list_entities()
-- (in lists.sql), and independently verified behaviorally against the live
-- functions using three real signed-in test accounts:
--   - Return columns/order for get_profile_starred_entities: id, name,
--     address, city, state, lat, lng, type_name, cuisine_name, status -
--     confirmed via a live call against a real starred entity.
--   - Return columns/order for get_profile_lists: id, name, description,
--     visibility, item_count - confirmed via live calls against real
--     public/friends/private test lists.
--   - Visibility semantics confirmed live: a stranger (or a fully
--     unauthenticated/anon caller) sees only the target's public lists and
--     zero starred entities; an accepted friend additionally sees
--     friends-visibility lists and the real starred list; the target
--     viewing themselves (target_user_id = auth.uid()) sees everything,
--     including private lists.
--   - GRANT EXECUTE was confirmed to include `anon`, not just
--     `authenticated` - both functions returned correct (not
--     permission-denied) results when called with no session at all.
-- If this ever needs to be byte-exact, re-pull via
-- `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname IN
-- ('get_profile_starred_entities', 'get_profile_lists');` and replace this
-- file's function bodies with the real text.
--
-- Safe to re-run (idempotent) if replayed against a fresh database.

CREATE OR REPLACE FUNCTION public.get_profile_starred_entities(target_user_id uuid)
 RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision, type_name text, cuisine_name text, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name,
        e.status
    FROM stars s
    JOIN entities e            ON e.id = s.entity_id
    JOIN entity_categories ec  ON ec.entity_id = e.id
    JOIN categories c          ON c.id = ec.category_id
    JOIN categories top        ON top.path = subpath(c.path, 0, 1)
    WHERE s.user_id = target_user_id
      AND (
          target_user_id = auth.uid()
          OR EXISTS (
              SELECT 1 FROM friendships f
              WHERE f.status = 'accepted'
                AND ((f.requester_id = auth.uid() AND f.addressee_id = target_user_id)
                  OR (f.addressee_id = auth.uid() AND f.requester_id = target_user_id))
          )
      )
    ORDER BY e.name;
$function$;

CREATE OR REPLACE FUNCTION public.get_profile_lists(target_user_id uuid)
 RETURNS TABLE(id uuid, name text, description text, visibility text, item_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
    SELECT
        l.id, l.name, l.description, l.visibility,
        (SELECT count(*)::integer FROM list_items li WHERE li.list_id = l.id) AS item_count
    FROM lists l
    WHERE l.owner_id = target_user_id
      AND (
          l.owner_id = auth.uid()
          OR l.visibility = 'public'
          OR (
              l.visibility = 'friends'
              AND EXISTS (
                  SELECT 1 FROM friendships f
                  WHERE f.status = 'accepted'
                    AND ((f.requester_id = auth.uid() AND f.addressee_id = l.owner_id)
                      OR (f.addressee_id = auth.uid() AND f.requester_id = l.owner_id))
              )
          )
      )
    ORDER BY l.created_at DESC;
$function$;

GRANT EXECUTE ON FUNCTION public.get_profile_starred_entities(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_profile_lists(uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
