-- Adds city/state to entities, and a lookup function returning a signed-in
-- user's starred entities with everything the /profile page's Map and
-- Browse tabs need in one call: id, name, address, city, state, lat, lng,
-- type_name (top-level category, e.g. "Restaurants"), cuisine_name (the
-- specific tag, e.g. "Pasta"), and recommended_by/recommended_count (which
-- of the user's accepted friends also starred this place - identical logic
-- to search_entities' recommendation fields, so the profile page's badge
-- and the search page's label can never disagree).
--
-- Already applied directly in the Supabase SQL Editor; this file is the
-- tracked record of that change, confirmed against the live function via
-- `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname =
-- 'get_my_starred_entities';` - safe to re-run (idempotent) if replayed
-- against a fresh database.
--
-- Note: an entity tagged with multiple categories (e.g. a place that's
-- both "Mexican" and "Bar") produces one row per category tag, joined
-- through entity_categories - callers need to de-duplicate by entity id
-- when not filtering to a specific cuisine.
--
-- UPDATE: recommended_by is now jsonb (an array of {name, handle} objects)
-- rather than text[] of already-resolved display strings, so the
-- frontend's "Starred by X" label can link each name to /u/[handle] - see
-- supabase/add_handle_to_recommended_by.sql, which is also the tracked
-- record of *when* this changed (this file mirrors the current live
-- shape, confirmed via pg_get_functiondef, same convention as
-- search_entities.sql).

ALTER TABLE entities ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS state text;

-- Changing RETURNS TABLE columns requires DROP + CREATE, not just CREATE OR
-- REPLACE (Postgres won't let you change an existing function's return
-- shape in place) - included here so this file replays cleanly even if the
-- pre-recommendation-fields version of this function already exists.
DROP FUNCTION IF EXISTS public.get_my_starred_entities();

CREATE OR REPLACE FUNCTION public.get_my_starred_entities()
 RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision, type_name text, cuisine_name text, recommended_by jsonb, recommended_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name,
        -- Identical logic to search_entities' recommended_by/recommended_count,
        -- so the profile badge and search-page label can never disagree.
        (
            SELECT jsonb_agg(jsonb_build_object('name', name, 'handle', handle) ORDER BY starred_at)
            FROM (
                SELECT COALESCE(p.display_name, p.handle) AS name, p.handle AS handle, fs.created_at AS starred_at
                FROM stars fs
                JOIN profiles p ON p.id = fs.user_id
                JOIN friendships f ON (
                    (f.requester_id = auth.uid() AND f.addressee_id = fs.user_id)
                    OR (f.addressee_id = auth.uid() AND f.requester_id = fs.user_id)
                )
                WHERE fs.entity_id = e.id AND f.status = 'accepted'
                ORDER BY fs.created_at
                LIMIT 2
            ) top_two
        ) AS recommended_by,
        (
            SELECT count(*)::integer
            FROM stars fs2
            JOIN friendships f2 ON (
                (f2.requester_id = auth.uid() AND f2.addressee_id = fs2.user_id)
                OR (f2.addressee_id = auth.uid() AND f2.requester_id = fs2.user_id)
            )
            WHERE fs2.entity_id = e.id AND f2.status = 'accepted'
        ) AS recommended_count
    FROM stars s
    JOIN entities e            ON e.id = s.entity_id
    JOIN entity_categories ec  ON ec.entity_id = e.id
    JOIN categories c          ON c.id = ec.category_id
    JOIN categories top        ON top.path = subpath(c.path, 0, 1)
    WHERE s.user_id = auth.uid()
    ORDER BY e.name;
$function$;

-- SECURITY DEFINER means this runs as its owner regardless of caller, so
-- only EXECUTE needs to be granted - no direct table access is needed for
-- authenticated on entities/entity_categories/categories/stars/friendships
-- because of this function (see supabase/grants_reference.sql for what IS
-- needed directly, e.g. stars INSERT/DELETE for the star toggle button).
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default - explicitly revoked
-- so anon can't invoke this via that implicit grant (see the standing rule
-- in grants_reference.sql).
REVOKE EXECUTE ON FUNCTION public.get_my_starred_entities() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_starred_entities() TO authenticated;

NOTIFY pgrst, 'reload schema';
