-- Adds city/state to entities, and a lookup function returning a signed-in
-- user's starred entities with everything the /profile page's Map and
-- Browse tabs need in one call: id, name, address, city, state, lat, lng,
-- type_name (top-level category, e.g. "Restaurants"), and cuisine_name
-- (the specific tag, e.g. "Pasta").
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

ALTER TABLE entities ADD COLUMN IF NOT EXISTS city text;
ALTER TABLE entities ADD COLUMN IF NOT EXISTS state text;

CREATE OR REPLACE FUNCTION public.get_my_starred_entities()
 RETURNS TABLE(id uuid, name text, address text, city text, state text, lat double precision, lng double precision, type_name text, cuisine_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
    SELECT
        e.id, e.name, e.address, e.city, e.state,
        ST_Y(e.location::geometry) AS lat,
        ST_X(e.location::geometry) AS lng,
        top.name AS type_name,
        c.name AS cuisine_name
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
-- authenticated on entities/entity_categories/categories/stars because of
-- this function (see supabase/grants_reference.sql for what IS needed
-- directly, e.g. stars INSERT/DELETE for the star toggle button).
GRANT EXECUTE ON FUNCTION public.get_my_starred_entities() TO authenticated;

NOTIFY pgrst, 'reload schema';
